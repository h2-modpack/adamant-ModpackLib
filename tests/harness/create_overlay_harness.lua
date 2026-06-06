local createLibHarness = require("tests/harness/create_lib_harness")

local function createModUtilMock()
    return {
        Path = {
            Wrap = function() end,
            Override = function() end,
            Restore = function() end,
            Context = {
                Wrap = function() end,
            },
        },
    }
end

local function createGameState(opts)
    opts = opts or {}
    local game = {
        screenData = opts.ScreenData or {
            HUD = {
                ComponentData = {},
            },
        },
        hudScreen = opts.HUDScreen or {
            Components = {},
        },
        showingCombatUI = opts.ShowingCombatUI ~= false,
        nextComponentId = opts.nextComponentId or 100,
        modifyTextBox = opts.ModifyTextBox or function() end,
        setAlpha = opts.SetAlpha or function() end,
        destroy = opts.Destroy or function() end,
    }

    game.createComponentFromData = opts.CreateComponentFromData or function(_, data)
        game.nextComponentId = game.nextComponentId + 1
        return {
            Id = game.nextComponentId,
            Name = data.Name,
        }
    end

    return game
end

local function createGameDeps(game)
    return {
        cache = {
            CurrentRun = function()
                return rawget(_G, "CurrentRun")
            end,
        },
        runData = {
            SetupRunData = function() end,
        },
        overlays = {
            ScreenData = function()
                return game.screenData
            end,
            HUDScreen = function()
                return game.hudScreen
            end,
            ShowingCombatUI = function()
                return game.showingCombatUI
            end,
            ModifyTextBox = function(args)
                return game.modifyTextBox(args)
            end,
            SetAlpha = function(args)
                return game.setAlpha(args)
            end,
            CreateComponentFromData = function(componentData, data)
                return game.createComponentFromData(componentData, data)
            end,
            Destroy = function(args)
                return game.destroy(args)
            end,
        },
    }
end

local function createModuleState(base, config, definition)
    local state = base.moduleState.create(config, definition)
    return state.persistentState, state.stagedState
end

local function createOverlayHarness(opts)
    opts = opts or {}
    local game = createGameState(opts)
    local modutil = opts.modutil or createModUtilMock()
    local base = createLibHarness({
        config = opts.config,
        public = opts.public,
        runtime = opts.runtime,
        plugin = opts.plugin,
        rom = opts.rom,
        chalk = opts.chalk,
        modutil = modutil,
        gameDeps = opts.gameDeps or createGameDeps(game),
        importOverrides = opts.importOverrides,
    })

    return {
        harness = base,
        public = base.public,
        config = base.config,
        runtime = base.runtime,
        overlayRegistry = base.registry.overlays,
        rendererState = base.registry.overlays.renderer,
        retainedState = base.registry.overlays.retained,
        overlays = base.overlays,
        managedModule = base.managedModule,
        moduleState = base.moduleState,
        createSystem = base.createSystem,
        game = game,
        modutil = modutil,

        createModuleState = function(config, definition)
            return createModuleState(base, config, definition)
        end,

        createModuleWithOverlays = function(pluginGuid, declareOverlays, moduleOpts)
            moduleOpts = moduleOpts or {}
            local definition = base.managedModule.prepareDefinition({}, {
                id = moduleOpts.id or "OverlayHost",
                name = moduleOpts.name or "Overlay Host",
                storage = moduleOpts.storage or {},
            })
            local store, stagedState = createModuleState(base, moduleOpts.config or {
                Enabled = true,
                DebugMode = false,
            }, definition)
            local overlayDeclarations = base.overlaysBundle.declarations.create()
            local overlayRegistrar = {
                order = base.overlaysBundle.order,
                createLine = function(name, spec)
                    return base.overlaysBundle.declarations.declareLine(
                        overlayDeclarations,
                        "module.overlays.createLine",
                        name,
                        spec)
                end,
                createTable = function(name, spec)
                    return base.overlaysBundle.declarations.declareTable(
                        overlayDeclarations,
                        "module.overlays.createTable",
                        name,
                        spec)
                end,
                onCommit = function(callback)
                    return base.overlaysBundle.declarations.declareCommit(
                        overlayDeclarations,
                        "module.overlays.onCommit",
                        callback)
                end,
                onInterval = function(name, seconds, callback, intervalOpts)
                    return base.overlaysBundle.declarations.declareInterval(
                        overlayDeclarations,
                        "module.overlays.onInterval",
                        name,
                        seconds,
                        callback,
                        intervalOpts)
                end,
                afterHook = function(path, callback)
                    return base.overlaysBundle.declarations.declareAfterHook(
                        overlayDeclarations,
                        "module.overlays.afterHook",
                        path,
                        callback)
                end,
            }
            if type(declareOverlays) == "function" then
                declareOverlays(overlayRegistrar, nil, store)
            end
            local host = base.managedModule.create({
                pluginGuid = pluginGuid,
                definition = definition,
                persistentState = store,
                stagedState = stagedState,
                mutationBundle = {
                    patchMutation = moduleOpts.patchMutation,
                },
                overlayDeclarations = overlayDeclarations,
                onCommit = moduleOpts.onCommit,
                drawTab = function() end,
            })
            return host, host, store, stagedState, definition
        end,
    }
end

return createOverlayHarness
