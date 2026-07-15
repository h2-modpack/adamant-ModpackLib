local createLibHarness = require("tests/harness/create_lib_harness")

local function createManagedModuleHarness(harnessOpts)
    local base = createLibHarness(harnessOpts)
    local h = {
        harness = base,
        public = base.public,
        config = base.config,
        runtime = base.runtime,
        rom = base.rom,
        managedModule = base.managedModule,
        moduleBundle = base.moduleBundle,
        moduleState = base.moduleState,
        managedModuleLifecycle = base.managedModuleLifecycle,
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
        return self.managedModule.prepareDefinition(owner or {}, definition, structuralOpts)
    end

    function h:createModuleState(config, definition)
        return self.harness:createModuleState(config, definition)
    end

    function h:createModuleOrThrow(opts)
        return self.moduleBundle.createModuleOrThrow(opts)
    end

    function h:writeNativeConfig(pluginGuid, values)
        return self.harness:writeNativeConfig(pluginGuid, values)
    end

    function h:readNativeConfig(pluginGuid)
        return self.harness:readNativeConfig(pluginGuid)
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

    local function adaptReloadCallback(callback)
        if type(callback) ~= "function" then
            return callback
        end
        return function(callbackHost, runtime, reload)
            return callback(runtime, callbackHost, reload)
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

    function h:createManagedModule(pluginGuid, moduleOpts)
        moduleOpts = moduleOpts or {}
        local host, store = self.managedModule.create({
            pluginGuid = pluginGuid,
            definition = moduleOpts.definition,
            persistentState = moduleOpts.persistentState,
            stagedState = moduleOpts.stagedState,
            mutationBundle = {
                patchMutation = adaptPatchMutation(moduleOpts.patchMutation),
            },
            onCommit = adaptCommitCallback(moduleOpts.onCommit),
            onReload = adaptReloadCallback(moduleOpts.onReload),
            drawTab = adaptDrawCallback(moduleOpts.drawTab),
            drawQuickContent = adaptDrawCallback(moduleOpts.drawQuickContent),
        })
        return host, host, store
    end

    function h:createActivatedManagedModule(pluginGuid, moduleOpts)
        local host, _, store = self:createManagedModule(pluginGuid, moduleOpts)
        local ok, err = host.activate()
        return host, host, ok, err, store
    end

    function h:liveModule(pluginGuid)
        return self.managedModule.getLiveModule(pluginGuid)
    end

    return h
end

return createManagedModuleHarness
