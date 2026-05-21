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
        moduleRuntimeRegistry = base.moduleRuntimeRegistry,
        hostState = base.hostState,
        coordinator = base.coordinator,
        integrations = base.integrations,
        overlays = base.overlays,
        fallbackUi = base.fallbackUi,
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
        return state.store, state.session
    end

    function h:createModuleOrThrow(opts)
        return self.moduleBundle.createModuleOrThrow(opts)
    end

    function h:createHost(pluginGuid, hostOpts)
        hostOpts = hostOpts or {}
        local host, authorHost, authorStore = self.moduleHost.create({
            pluginGuid = pluginGuid,
            definition = hostOpts.definition,
            store = hostOpts.store,
            session = hostOpts.session,
            onSettingsCommitted = hostOpts.onSettingsCommitted,
            drawTab = hostOpts.drawTab,
            drawQuickContent = hostOpts.drawQuickContent,
        })
        if hostOpts.patchMutation ~= nil then
            authorHost.mutation.patch(hostOpts.patchMutation)
        end
        return host, authorHost, authorStore
    end

    function h:createActivatedHost(pluginGuid, hostOpts)
        local host, authorHost, authorStore = self:createHost(pluginGuid, hostOpts)
        local ok, err = authorHost.activate()
        return host, authorHost, ok, err, authorStore
    end

    function h:createPreparedStore(config, rawDefinition)
        local definition = self:prepareDefinition({}, rawDefinition)
        local store, session = self:createModuleState(config, definition)
        return definition, store, session
    end

    function h:liveHost(pluginGuid)
        return self.moduleHost.getLiveHost(pluginGuid)
    end

    return h
end

return createModuleHostHarness
