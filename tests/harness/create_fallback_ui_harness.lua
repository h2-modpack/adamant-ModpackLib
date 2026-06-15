local createLibHarness = require("tests/harness/create_lib_harness")

local PLUGIN_GUID = "test-fallback-ui-module"
local FALLBACK_OWNER = "adamant-lib.fallback-hud"
local FALLBACK_ROW_KEY = "middleRightStack\0" .. FALLBACK_OWNER .. ":marker"

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
        screenCenterX = opts.ScreenCenterX or 960,
        screenHeight = opts.ScreenHeight or 1080,
        nextComponentId = opts.nextComponentId or 100,
        setupRunData = opts.SetupRunData or function() end,
        modifyTextBox = opts.ModifyTextBox or function() end,
        setAlpha = opts.SetAlpha or function() end,
        destroy = opts.Destroy or function() end,
    }

    game.createComponentFromData = opts.CreateComponentFromData or function(_, data)
        game.nextComponentId = game.nextComponentId + 1
        return {
            Id = data.Name or game.nextComponentId,
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
            SetupRunData = function()
                return game.setupRunData()
            end,
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
            ScreenCenterX = function()
                return game.screenCenterX
            end,
            ScreenHeight = function()
                return game.screenHeight
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

local function createFallbackUiHarness(opts)
    opts = opts or {}
    local game = createGameState(opts)
    local base = createLibHarness({
        config = opts.config,
        public = opts.public,
        runtime = opts.runtime,
        plugin = opts.plugin,
        rom = opts.rom,
        chalk = opts.chalk,
        modutil = opts.modutil,
        modutilPlugin = opts.modutilPlugin,
        gameDeps = opts.gameDeps or createGameDeps(game),
        importOverrides = opts.importOverrides,
    })
    local h = {
        harness = base,
        public = base.public,
        config = base.config,
        runtime = base.runtime,
        rom = base.rom,
        game = game,
        fallbackUi = base.fallbackUi,
        overlays = base.overlays,
        managedModule = base.managedModule,
        moduleState = base.moduleState,
        registry = base.registry,
        moduleRegistry = base.moduleRegistry,
        coordinator = base.coordinator,
        overlayRegistry = base.registry.overlays,
        rendererState = base.registry.overlays.renderer,
        retainedState = base.registry.overlays.retained,
        warnings = {},
    }

    h.rom.ImGuiCond = { FirstUseEver = 1 }

    function h:captureWarnings()
        self.warnings = {}
        self.config.DebugMode = true
        self.previousPrint = self.harness.env.print
        self.harness.env.print = function(msg)
            self.warnings[#self.warnings + 1] = msg
        end
    end

    function h:restoreWarnings()
        self.config.DebugMode = false
        self.harness.env.print = self.previousPrint
        self.previousPrint = nil
    end

    function h:installModule(host, pluginGuid)
        self.moduleRegistry.setLiveModule(pluginGuid or PLUGIN_GUID, host)
    end

    function h:createModuleState(config, definition)
        return self.harness:createModuleState(config, definition)
    end

    function h:createLibModule(pluginGuid, moduleOpts)
        moduleOpts = moduleOpts or {}
        local definition = self.managedModule.prepareDefinition({}, {
            modpack = moduleOpts.modpack or "fallback-pack",
            id = moduleOpts.id or "FallbackUiTest",
            name = moduleOpts.name or "Fallback UI Test",
            storage = {},
        })
        local store, stagedState = self:createModuleState({
            Enabled = moduleOpts.enabled ~= false,
            DebugMode = moduleOpts.debugMode == true,
        }, definition)
        local host = self.managedModule.create({
            pluginGuid = pluginGuid,
            definition = definition,
            persistentState = store,
            stagedState = stagedState,
            drawTab = function() end,
        })
        return host, host
    end

    function h:createActivatedLibModule(pluginGuid, moduleOpts)
        moduleOpts = moduleOpts or {}
        local host = self:createLibModule(pluginGuid, moduleOpts)
        if moduleOpts.attachFallbackUi == true then
            self.fallbackUi.attachGuiOnce(host, moduleOpts.registerGui or function() end)
        end
        local ok, err = host.activate()
        assert(ok, tostring(err))
        return self.managedModule.getLiveModule(pluginGuid), host
    end

    function h:getFallbackUiRuntime(pluginGuid)
        return self.registry.fallback.runtimes[pluginGuid]
    end

    function h:installFallbackRuntime(module)
        local receipt = self.fallbackUi.installForModule(module)
        local ok, err = receipt.commit()
        assert(ok, tostring(err))
        return self:getFallbackUiRuntime(module.getOwnerId())
    end

    function h:getFallbackMarkerRow()
        self.fallbackUi.createFallbackMarker()
        return self.rendererState.stackRows[FALLBACK_ROW_KEY]
    end

    function h:countUiSuppressors()
        local count = 0
        for _ in pairs(self.overlayRegistry.uiSuppressors) do
            count = count + 1
        end
        return count
    end

    return h
end

return createFallbackUiHarness
