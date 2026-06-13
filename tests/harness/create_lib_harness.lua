local fakeEngine = require("tests/harness/fake_engine")
local nativeConfigFixture = require("tests/harness/native_config_fixture")

local function createLibHarness(opts)
    opts = opts or {}

    local config = opts.config or { DebugMode = false }
    local public = opts.public or {}

    local runtimeRoot = opts.runtime or {}
    local plugin = opts.plugin or { guid = "test-module" }
    local nativeConfigRoot = opts.nativeConfigRoot
        or ("/tmp/adamant-modpacklib-tests-" .. tostring(os.clock()):gsub("[^%d]", ""))
    local imports = {}
    local importOverrides = opts.importOverrides or {}
    local callbacks = opts.callbacks or fakeEngine.createCallbacks()
    local env = fakeEngine.createBaseEnv({
        callbacks = callbacks,
        public = public,
        config = config,
        plugin = plugin,
        runtimeRoot = runtimeRoot,
        rom = opts.rom,
        chalk = opts.chalk,
        modutilPlugin = opts.modutilPlugin,
        modUtilRuntime = opts.modutil or opts.modUtilRuntime,
        CurrentRun = opts.CurrentRun,
        ScreenData = opts.ScreenData,
        HUDScreen = opts.HUDScreen,
        ShowingCombatUI = opts.ShowingCombatUI,
        ModifyTextBox = opts.ModifyTextBox,
        SetAlpha = opts.SetAlpha,
        CreateComponentFromData = opts.CreateComponentFromData,
        Destroy = opts.Destroy,
        ImGuiComboFlags = opts.ImGuiComboFlags or { NoPreview = 64 },
        ImGuiCol = opts.ImGuiCol,
        ImGuiTreeNodeFlags = opts.ImGuiTreeNodeFlags or {},
        imports = imports,
        importOverrides = importOverrides,
        installImport = true,
    })
    local rom = env.rom
    nativeConfigFixture.configureRoot(rom, nativeConfigRoot)

    local externals = {
        rom = rom,
        chalk = opts.chalk or rom.mods['SGG_Modding-Chalk'],
        plugin = plugin,
        modutil = rom.mods['SGG_Modding-ModUtil'],
        gameDeps = opts.gameDeps,
    }

    local core = env.import('core/init.lua', nil, {
        config = config,
        externals = externals,
    })

    local harness = {
        public = public,
        lib = public,
        config = config,
        runtime = env.AdamantModpackLib_Runtime,
        core = core,
        imports = imports,
        import = env.import,
        env = env,
        externals = externals,
        rom = rom,
        nativeConfigRoot = nativeConfigRoot,
        game = rom.game,
        chalk = externals.chalk,
        modutil = env.ModUtil,
        modutilPlugin = externals.modutil,
        plugin = plugin,

        logging = imports["core/logging/logging.lua"],
        values = imports["core/helpers/values.lua"],
        gameDeps = externals.gameDeps or imports["core/game_deps/game_deps.lua"],
        cacheBundle = imports["core/cache/00_init.lua"],
        cache = imports["core/cache/00_init.lua"].service,
        storage = imports["core/storage/00_init.lua"],
        registry = imports["core/lib_bootstrap/registry.lua"],
        moduleRegistry = imports["core/lib_bootstrap/module_registry.lua"],
        systemScope = imports["core/lib_bootstrap/system_scope.lua"],
        moduleState = imports["core/module_state/00_init.lua"],
        uiActions = imports["core/module_state/actions/ui_actions.lua"],
        coordinator = imports["core/modpack/coordination.lua"],
        sharedBundle = imports["core/shared/00_init.lua"],
        shared = imports["core/shared/00_init.lua"].service,
        hooksBundle = imports["core/hooks/00_init.lua"],
        hooks = imports["core/hooks/00_init.lua"].service,
        overlaysBundle = imports["core/overlays/00_init.lua"],
        overlays = imports["core/overlays/00_init.lua"].service,
        mutationBundle = imports["core/mutations/00_init.lua"],
        mutation = imports["core/mutations/00_init.lua"].service,
        mutationPlan = imports["core/mutations/00_init.lua"].plan,
        widgetsBundle = imports["core/widgets/00_init.lua"],
        widgets = imports["core/widgets/00_init.lua"].widgets,
        nav = imports["core/widgets/00_init.lua"].nav,
        uiDraw = imports["core/widgets/00_init.lua"].uiDraw,
        moduleDefinition = imports["core/module_bootstrap/definition.lua"],
        managedModuleLifecycle = imports["core/module_bootstrap/managed_module_lifecycle.lua"],
        managedModule = imports["core/module_bootstrap/managed_module.lua"],
        moduleBundle = imports["core/module_bootstrap/module.lua"],
        fallbackUiBundle = imports["core/fallback/fallback_ui.lua"],
        fallbackUi = imports["core/fallback/fallback_ui.lua"].service,
    }
    harness.externals.gameDeps = harness.gameDeps
    function harness:writeNativeConfig(pluginGuid, values)
        nativeConfigFixture.write(self.nativeConfigRoot, pluginGuid, values)
    end
    function harness:readNativeConfig(pluginGuid)
        local file = assert(io.open(nativeConfigFixture.combinePath(self.nativeConfigRoot, pluginGuid .. ".cfg"), "r"))
        local contents = file:read("*a")
        file:close()
        return contents
    end
    function harness:createConfigFixture(configValues, pluginGuid)
        return nativeConfigFixture.create(self.nativeConfigRoot, configValues, pluginGuid)
    end
    function harness:createModuleState(configValues, definition, createStateOpts)
        createStateOpts = createStateOpts or {}
        local configPath = createStateOpts.configPath or self:createConfigFixture(
            configValues or {},
            createStateOpts.pluginGuid
        )
        local createOpts = {}
        for key, value in pairs(createStateOpts) do
            createOpts[key] = value
        end
        createOpts.configPath = configPath
        local state = self.moduleState.create(definition, createOpts)
        return state.persistentState, state.stagedState, configPath
    end
    function harness.createSystem(ownerId)
        return harness.systemScope.create(ownerId, {
            hooks = harness.hooksBundle.system,
            overlays = harness.overlaysBundle.system,
        })
    end

    return harness
end

return createLibHarness
