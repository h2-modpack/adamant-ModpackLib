local createLibHarness = require("tests/harness/create_lib_harness")

local function createModuleHostHarness(harnessOpts)
    local base = createLibHarness(harnessOpts)
    local h = {
        harness = base,
        public = base.public,
        config = base.config,
        runtime = base.runtime,
        rom = base.rom,
        moduleHost = base.moduleHost,
        moduleBundle = base.moduleBundle,
        moduleState = base.moduleState,
        hostLifecycle = base.hostLifecycle,
        registry = base.registry,
        moduleRegistry = base.moduleRegistry,
        coordinator = base.coordinator,
        sharedBundle = base.sharedBundle,
        shared = base.shared,
        overlays = base.overlays,
        fallbackUi = base.fallbackUi,
        fallbackUiBundle = base.fallbackUiBundle,
        warnings = {},
    }

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

    function h:prepareDefinition(owner, definition, structuralOpts)
        return self.moduleHost.prepareDefinition(owner or {}, definition, structuralOpts)
    end

    function h:createModuleState(config, definition)
        local state = self.moduleState.create(config, definition)
        return state.persistentState, state.stagedState
    end

    function h:createModuleOrThrow(opts)
        return self.moduleBundle.createModuleOrThrow(opts)
    end

    local function adaptDrawCallback(callback)
        if type(callback) ~= "function" then
            return callback
        end
        return function(callbackHost, ui)
            return callback(ui.draw, ui.data, ui.actions, ui, callbackHost)
        end
    end

    local function adaptCommitCallback(callback)
        if type(callback) ~= "function" then
            return callback
        end
        return function(callbackHost, runtime, commit)
            return callback(runtime, callbackHost, commit)
        end
    end

    local function adaptPatchMutation(callback)
        if type(callback) ~= "function" then
            return callback
        end
        return function(callbackHost, runtime, plan)
            return callback(plan, callbackHost, runtime.data, runtime, callbackHost)
        end
    end

    function h:createHost(pluginGuid, hostOpts)
        hostOpts = hostOpts or {}
        local host, store = self.moduleHost.create({
            pluginGuid = pluginGuid,
            definition = hostOpts.definition,
            persistentState = hostOpts.persistentState,
            stagedState = hostOpts.stagedState,
            mutationBundle = {
                patchMutation = adaptPatchMutation(hostOpts.patchMutation),
            },
            onCommit = adaptCommitCallback(hostOpts.onCommit),
            drawTab = adaptDrawCallback(hostOpts.drawTab),
            drawQuickContent = adaptDrawCallback(hostOpts.drawQuickContent),
        })
        return host, host, store
    end

    function h:createActivatedHost(pluginGuid, hostOpts)
        local host, _, store = self:createHost(pluginGuid, hostOpts)
        local ok, err = host.activate()
        return host, host, ok, err, store
    end

    function h:liveModule(pluginGuid)
        return self.moduleHost.getLiveModule(pluginGuid)
    end

    return h
end

return createModuleHostHarness
