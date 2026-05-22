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
        moduleHost = base.moduleHost,
        moduleState = base.moduleState,
        registry = base.registry,
        hostRegistry = base.hostRegistry,
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

    function h:installHost(host, pluginGuid)
        self.hostRegistry.setLiveHost(pluginGuid or PLUGIN_GUID, host)
    end

    function h:createModuleState(config, definition)
        local state = self.moduleState.create(config, definition)
        return state.persistentState, state.stagedState
    end

    function h:createLibHost(pluginGuid, hostOpts)
        hostOpts = hostOpts or {}
        local definition = self.moduleHost.prepareDefinition({}, {
            modpack = hostOpts.modpack or "fallback-pack",
            id = hostOpts.id or "FallbackUiTest",
            name = hostOpts.name or "Fallback UI Test",
            storage = {},
        })
        local store, stagedState = self:createModuleState({
            Enabled = hostOpts.enabled ~= false,
            DebugMode = hostOpts.debugMode == true,
        }, definition)
        local host, authorHost = self.moduleHost.create({
            pluginGuid = pluginGuid,
            definition = definition,
            persistentState = store,
            stagedState = stagedState,
            drawTab = function() end,
        })
        return host, authorHost
    end

    function h:createActivatedLibHost(pluginGuid, hostOpts)
        hostOpts = hostOpts or {}
        local host, authorHost = self:createLibHost(pluginGuid, hostOpts)
        if hostOpts.attachFallbackUi == true then
            authorHost.fallbackUi.attachGuiOnce(hostOpts.registerGui or function() end)
        end
        local ok, err = authorHost.activate()
        assert(ok, tostring(err))
        return host, authorHost
    end

    function h:getFallbackUiRuntime(pluginGuid)
        return self.registry.fallback.runtimes[pluginGuid]
    end

    function h:installFallbackRuntime(host)
        local receipt = self.fallbackUi.installForHost(host)
        local ok, err = receipt.commit()
        assert(ok, tostring(err))
        return self:getFallbackUiRuntime(host.getHostId())
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
