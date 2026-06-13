-- =============================================================================
-- Test utilities: load Lib and expose shared modpack test helpers.
-- =============================================================================
-- luacheck: globals LibConfig LibTestImports Warnings lib CaptureWarnings RestoreWarnings
-- luacheck: globals GetRuntimeLiveModules SetRuntimeLiveModule LibStorage LibModuleState LibManagedModule LibOverlays
-- luacheck: globals CreateModuleState InstallWindowImGuiStub CreateModpackHudStub import ModpackTestApi CreateModpackHarness
-- luacheck: globals MockModuleRegistry _originalPrint print

local fakeEngine = require("tests/harness/fake_engine")
local nativeConfigFixture = require("tests/harness/native_config_fixture")

local libPublic = {}
local libPlugin = { guid = "adamant-ModpackLib" }

LibConfig = {
    DebugMode = false,
    Diagnostics = {
        configBackend = {
            label = "Config Backend Diagnostics",
            enabled = false,
        },
    },
}

local TEST_IMGUI_TREE_NODE_FLAGS = {
    None = 0,
    Selected = 1,
    Framed = 2,
    AllowOverlap = 4,
    NoTreePushOnOpen = 8,
    NoAutoOpenOnLog = 16,
    DefaultOpen = 32,
    OpenOnDoubleClick = 64,
    OpenOnArrow = 128,
    Leaf = 256,
    Bullet = 512,
    FramePadding = 1024,
    SpanAvailWidth = 2048,
    SpanFullWidth = 4096,
    NavLeftJumpsBackHere = 8192,
    CollapsingHeader = 26,
}

LibTestImports = {}

local libEnv = fakeEngine.createBaseEnv({
    public = libPublic,
    plugin = libPlugin,
    config = LibConfig,
    imports = LibTestImports,
    installImport = true,
    ImGuiTreeNodeFlags = TEST_IMGUI_TREE_NODE_FLAGS,
    chalkOriginal = function(rawConfig)
        return rawConfig
    end,
})
assert(loadfile("src/main.lua", "t", libEnv))()

rom = libEnv.rom
local libRuntimeRoot = libEnv.AdamantModpackLib_Runtime

Warnings = {}

lib = libEnv.public
rom.mods['adamant-ModpackLib'] = lib

function CaptureWarnings()
    Warnings = {}
    LibConfig.DebugMode = true
    _originalPrint = print
    print = function(msg)
        table.insert(Warnings, msg)
    end
end

function RestoreWarnings()
    LibConfig.DebugMode = false
    print = _originalPrint or print
    Warnings = {}
end

function GetRuntimeLiveModules()
    local registry = assert(libRuntimeRoot.registry, "Lib registry missing")
    local modules = assert(registry.modules, "module registry missing")
    return assert(modules.live, "runtime live modules missing")
end

function SetRuntimeLiveModule(pluginGuid, liveModule)
    local liveModules = GetRuntimeLiveModules()
    local previousLiveModule = liveModules[pluginGuid]
    liveModules[pluginGuid] = liveModule
    return previousLiveModule
end

LibStorage = setmetatable({}, {
    __index = function(_, key)
        return assert(LibTestImports["core/storage/00_init.lua"], "LibStorage test service missing")[key]
    end,
    __newindex = function(_, key, value)
        assert(LibTestImports["core/storage/00_init.lua"], "LibStorage test service missing")[key] = value
    end,
})
LibModuleState = setmetatable({}, {
    __index = function(_, key)
        return assert(LibTestImports["core/module_state/00_init.lua"], "LibModuleState test service missing")[key]
    end,
    __newindex = function(_, key, value)
        assert(LibTestImports["core/module_state/00_init.lua"], "LibModuleState test service missing")[key] = value
    end,
})
LibManagedModule = setmetatable({}, {
    __index = function(_, key)
        return assert(LibTestImports["core/module_bootstrap/managed_module.lua"], "LibManagedModule test service missing")[key]
    end,
    __newindex = function(_, key, value)
        assert(LibTestImports["core/module_bootstrap/managed_module.lua"], "LibManagedModule test service missing")[key] = value
    end,
})
local function GetLibOverlayService()
    local bundle = assert(LibTestImports["core/overlays/00_init.lua"], "LibOverlays test bundle missing")
    return assert(bundle.service, "LibOverlays test service missing")
end

local function GetLibOverlayState()
    return assert(LibTestImports["core/overlays/registry.lua"], "LibOverlays test registry missing")
end

LibOverlays = setmetatable({}, {
    __index = function(_, key)
        local state = GetLibOverlayState()
        if key == "uiSuppressors" or key == "nextUiSuppressorId" then
            return state[key]
        end
        return GetLibOverlayService()[key]
    end,
    __newindex = function(_, key, value)
        local state = GetLibOverlayState()
        if key == "uiSuppressors" or key == "nextUiSuppressorId" then
            state[key] = value
            return
        end
        GetLibOverlayService()[key] = value
    end,
})

local nativeConfigRoot = "/tmp/adamant-modpacklib-modpack-tests-" .. tostring(os.clock()):gsub("[^%d]", "")
nativeConfigFixture.configureRoot(rom, nativeConfigRoot)

function CreateModuleState(config, definition)
    config = config or {}
    local configPath = nativeConfigFixture.create(nativeConfigRoot, config)
    local state = LibModuleState.create(definition, {
        configPath = configPath,
    })
    return state.persistentState, state.stagedState
end

function InstallWindowImGuiStub(overrides)
    overrides = overrides or {}
    local previousImGui = rom.ImGui
    local imgui = previousImGui or {}
    local previousValues = {}
    for key, value in pairs(imgui) do
        previousValues[key] = value
    end
    local function noop() end
    local stub = {
        Begin = function() return true, true end,
        End = noop,
        SetNextWindowSize = noop,
        MenuItem = function() return true end,
        Checkbox = function(_, current) return current, false end,
        IsItemHovered = function() return false end,
        SetTooltip = noop,
        Separator = noop,
        SameLine = noop,
        Spacing = noop,
        GetWindowWidth = function() return 1000 end,
        BeginChild = function() return true end,
        EndChild = noop,
        Selectable = function() return false end,
        BeginCombo = function() return false end,
        EndCombo = noop,
        PushItemWidth = noop,
        PopItemWidth = noop,
        Text = noop,
        TextColored = noop,
        GetCursorPosX = function() return 0 end,
        GetContentRegionAvail = function() return 1000 end,
        GetCursorPosY = function() return 0 end,
        SetCursorPos = noop,
        SetCursorPosX = noop,
        GetFrameHeight = function() return 20 end,
        GetFrameHeightWithSpacing = function() return 24 end,
        GetStyle = function()
            return {
                FramePadding = { x = 4, y = 3 },
                ItemSpacing = { x = 8, y = 4 },
            }
        end,
        CalcTextSize = function(text) return #(tostring(text or "")) * 8 end,
        Button = function() return false end,
        InputText = function(_, value) return value, false end,
        GetClipboardText = function() return nil end,
        SetClipboardText = noop,
        CollapsingHeader = function() return false end,
        Indent = noop,
        Unindent = noop,
        PushID = noop,
        PopID = noop,
        PushStyleColor = noop,
        PopStyleColor = noop,
    }

    for key, value in pairs(overrides) do
        stub[key] = value
    end

    for key in pairs(imgui) do
        imgui[key] = nil
    end
    for key, value in pairs(stub) do
        imgui[key] = value
    end
    rom.ImGui = imgui
    return function()
        for key in pairs(imgui) do
            imgui[key] = nil
        end
        for key, value in pairs(previousValues) do
            imgui[key] = value
        end
        rom.ImGui = previousImGui
    end, imgui
end

function CreateModpackHudStub(overrides)
    overrides = overrides or {}
    local function noop() end
    local hud = {
        setModMarker = noop,
        markHashDirty = noop,
        flushPendingHash = noop,
        setMarkerVisible = noop,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    for key, value in pairs(overrides) do
        hud[key] = value
    end

    return hud
end

import = fakeEngine.buildImport(_ENV, {
    srcDir = "src",
})

local modpackPublic = lib.modpack

ModpackTestApi = setmetatable({
    public = modpackPublic,
}, {
    __index = function(_, key)
        return modpackPublic[key]
    end,
    __newindex = function(_, key, value)
        rawset(modpackPublic, key, value)
    end,
})

local logging = import("core/modpack/logging.lua")

local function makeModpackImportEnv(importOverrides)
    local env = fakeEngine.addFallback({}, _ENV)
    env.import = fakeEngine.buildImport(env, {
        srcDir = "src",
        importOverrides = importOverrides,
    })
    return env
end

local function mapConstructorOverrides(constructors)
    constructors = constructors or {}
    local importOverrides = {}
    local constructorPaths = {
        createModuleRegistry = "core/modpack/modules/registry.lua",
        createConfigHash = "core/modpack/hash/config_hash.lua",
        createHud = "core/modpack/hud/runtime.lua",
        createUI = "core/modpack/ui/window.lua",
        createTheme = "core/modpack/ui/theme.lua",
    }

    for name, path in pairs(constructorPaths) do
        if constructors[name] ~= nil then
            importOverrides[path] = function()
                return constructors[name]
            end
        end
    end

    return importOverrides
end

function CreateModpackHarness(opts)
    opts = opts or {}
    local harnessRom = opts.rom or rom
    local harnessLibConfig = opts.libConfig or LibConfig
    local harnessOverlaySurface = opts.overlaySurface or ModpackTestApi.createOverlaySurface()
    local getLiveModule = opts.getLiveModule or LibManagedModule.getLiveModule
    local harnessPackRegistry = opts.packRegistry or {}
    local harnessCoordination = opts.coordination or import("core/modpack/coordination.lua", nil, {
        logging = logging,
        coordinationRegistry = opts.coordinationRegistry or {},
    })
    local env = makeModpackImportEnv(mapConstructorOverrides(opts.constructors))
    local modpackCore = assert(loadfile("src/core/modpack/init.lua", "t", env))({
        rom = harnessRom,
        libConfig = harnessLibConfig,
        storage = LibStorage,
        coordination = harnessCoordination,
        overlaySurface = harnessOverlaySurface,
        getLiveModule = getLiveModule,
        packRegistry = harnessPackRegistry,
    })

    return {
        rom = harnessRom,
        libConfig = harnessLibConfig,
        overlaySurface = harnessOverlaySurface,
        modpack = modpackCore,
        coordination = harnessCoordination,
        packRegistry = harnessPackRegistry,
        registerCoordinator = modpackCore.registerCoordinator,
        createPack = modpackCore.createPack,
        createGuiCallbacks = modpackCore.createGuiCallbacks,
    }
end
local createModuleRegistry = import("core/modpack/modules/registry.lua", nil, {
    rom = rom,
    logging = logging,
})
local createTheme = import("core/modpack/ui/theme.lua", nil, {
    rom = rom,
})
local hashCodec = import("core/modpack/hash/codec.lua")
local createConfigHash = import("core/modpack/hash/config_hash.lua", nil, {
    rom = rom,
    hashCodec = hashCodec,
    logging = logging,
})
local createHud = import("core/modpack/hud/runtime.lua")
local createUI = import("core/modpack/ui/window.lua", nil, {
    rom = rom,
    logging = logging,
})

rawset(ModpackTestApi, "createOverlaySurface", function()
    return {
        order = {
            system = 0,
            modpack = 100,
            module = 1000,
            debug = 2000,
        },
        define = function()
            return true
        end,
        suppressForUi = function()
            return {
                release = function() end,
            }
        end,
        isUiSuppressed = function()
            return false
        end,
    }
end)

local function createTestUI(moduleRegistry, hud, theme, config, packId, windowTitle, numProfiles,
                            defaultProfiles, drawPackQuickContent, auditSavedProfiles, libConfig, overlaySurface)
    return createUI(moduleRegistry, hud, theme, config, packId, windowTitle, numProfiles, defaultProfiles,
        drawPackQuickContent, auditSavedProfiles, libConfig or LibConfig,
        overlaySurface or ModpackTestApi.createOverlaySurface())
end

local function createTestHud(packId, packIndex, configHash, theme, config, hideHashMarker, overlaySurface)
    return createHud(packId, packIndex, configHash, theme, config, hideHashMarker,
        overlaySurface or ModpackTestApi.createOverlaySurface())
end

rawset(ModpackTestApi, "createModuleRegistry", function(packId, testConfig, opts)
    local getLiveModule = opts and opts.getLiveModule or LibManagedModule.getLiveModule
    return createModuleRegistry(packId, testConfig, getLiveModule)
end)
rawset(ModpackTestApi, "createTheme", createTheme)
rawset(ModpackTestApi, "createConfigHash", function(moduleRegistry, testConfig, packId, storage)
    return createConfigHash(moduleRegistry, testConfig, packId, storage or LibStorage)
end)
rawset(ModpackTestApi, "createHud", createTestHud)
rawset(ModpackTestApi, "createUI", createTestUI)
rawset(ModpackTestApi, "logging", logging)
rawset(ModpackTestApi, "createUIRuntime", function(ctx)
    local runtimeCtx = {}
    for key, value in pairs(ctx) do
        runtimeCtx[key] = value
    end
    runtimeCtx.lib = runtimeCtx.lib or lib
    runtimeCtx.rom = runtimeCtx.rom or rom
    return import("core/modpack/ui/runtime.lua", nil, runtimeCtx)
end)
local profileTools = import("core/modpack/profiles/audit.lua", nil, {
    hashCodec = hashCodec,
    logging = logging,
})
rawset(ModpackTestApi, "normalizeProfiles", profileTools.normalizeProfiles)
rawset(ModpackTestApi, "auditSavedProfiles", function(packId, profileSlots, moduleRegistry, storage)
    return profileTools.auditSavedProfiles(packId, profileSlots, moduleRegistry, storage or LibStorage)
end)

config = { ModEnabled = true, DebugMode = false }

MockModuleRegistry = {}

local function prepareDefinition(definition)
    return LibManagedModule.prepareDefinition({}, definition)
end

local function makePersistedConfig(storage, overrides)
    local persisted = {
        Enabled = false,
        DebugMode = false,
    }
    local transientAliases = {}
    for _, root in ipairs(storage or {}) do
        if root.persist == false then
            transientAliases[root.alias] = true
        else
            persisted[root.alias] = overrides and overrides[root.alias] or root.default
        end
    end
    if overrides then
        for key, value in pairs(overrides) do
            if persisted[key] == nil and not transientAliases[key] then
                persisted[key] = value
            end
        end
    end
    return persisted
end

function MockModuleRegistry.create(moduleDefs)
    moduleDefs = moduleDefs or {}

    local moduleRegistry = {
        modules = {},
        modulesById = {},
        modulesWithQuickContent = {},
        tabOrder = {},
        live = {},
        snapshot = {},
    }

    local function addModule(def)
        local persisted = makePersistedConfig(def.storage, def.values)
        persisted.Enabled = def.enabled == true
        persisted.DebugMode = def.debug == true

        local definition = prepareDefinition({
            id = def.id,
            name = def.name or def.id,
            modpack = def.modpack or "test-pack",
            storage = def.storage or {},
            shortName = def.shortName,
            tooltip = def.tooltip,
        })
        local persistentState, stagedState = CreateModuleState(persisted, definition)
        local pluginGuid = def.pluginGuid or ("adamant-" .. def.id)
        local function adaptDraw(callback)
            if type(callback) ~= "function" then
                return callback
            end
            return function(callbackHost, ui)
                return callback(ui.draw, ui.data, ui.actions, ui, callbackHost)
            end
        end
        local function adaptPatch(callback)
            if type(callback) ~= "function" then
                return callback
            end
            return function(callbackHost, runtime, plan)
                return callback(plan, callbackHost, runtime and runtime.data or nil, runtime)
            end
        end
        local mutationBundle = {
            patchMutation = nil,
        }
        if def.patchPlan ~= nil then
            local mutations = assert(LibTestImports["core/mutations/00_init.lua"], "Lib mutation bundle missing")
            mutations.lifecycle.declarePatch(mutationBundle, adaptPatch(def.patchPlan))
        end
        local liveModule = LibManagedModule.create({
            pluginGuid = pluginGuid,
            definition = definition,
            persistentState = persistentState,
            stagedState = stagedState,
            mutationBundle = mutationBundle,
            drawTab = adaptDraw(def.DrawTab or function() end),
            drawQuickContent = adaptDraw(def.DrawQuickContent),
        })
        liveModule.activate()
        local module = {
            pluginGuid = pluginGuid,
            mod = {
                definition = definition,
                liveModule = liveModule,
            },
            definition = definition,
            id = definition.id,
            name = definition.name,
            shortName = definition.shortName,
            tooltip = definition.tooltip,
            modpack = definition.modpack,
            storage = definition.storage,
        }

        rom.mods[module.pluginGuid] = module.mod

        table.insert(moduleRegistry.modules, module)
        moduleRegistry.modulesById[module.id] = module

        if type(liveModule.drawQuickContent) == "function" then
            table.insert(moduleRegistry.modulesWithQuickContent, module)
        end

        module._tabLabel = definition.shortName or definition.name
        table.insert(moduleRegistry.tabOrder, module)
    end

    for _, def in ipairs(moduleDefs) do
        addModule(def)
    end

    function moduleRegistry.live.captureSnapshot()
        local snapshot = {
            liveModules = {},
        }

        for _, module in ipairs(moduleRegistry.modules) do
            local liveModule = LibManagedModule.getLiveModule(module.pluginGuid)
            snapshot.liveModules[module] = liveModule or false
        end

        return snapshot
    end

    function moduleRegistry.live.getLiveModule(entry)
        return LibManagedModule.getLiveModule(entry.pluginGuid)
    end

    function moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        local liveModule = snapshot.liveModules[entry]
        return liveModule or nil
    end

    function moduleRegistry.snapshot.isEntryEnabled(entry, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        return liveModule.read("Enabled") == true
    end

    function moduleRegistry.snapshot.affectsRunData(entry, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        return liveModule ~= nil and liveModule.affectsRunData() == true
    end

    function moduleRegistry.snapshot.setEntryEnabled(entry, enabled, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        return liveModule.setEnabled(enabled)
    end

    function moduleRegistry.snapshot.suspendForPackDisable(entry, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        return liveModule.suspendForPackDisable()
    end

    function moduleRegistry.snapshot.ensureSuspendedForPackDisable(entry, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        return liveModule.ensureSuspendedForPackDisable()
    end

    function moduleRegistry.snapshot.restoreForPackEnable(entry, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        return liveModule.restoreForPackEnable()
    end

    function moduleRegistry.snapshot.rollbackPackTransition(entry, receipt, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        return liveModule.rollbackPackTransition(receipt)
    end

    function moduleRegistry.snapshot.restorePackTransitionState(entry, receipt, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        return liveModule.restorePackTransitionState(receipt)
    end

    function moduleRegistry.snapshot.getStorageValue(module, alias, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(module, snapshot)
        return liveModule.read(alias)
    end

    function moduleRegistry.snapshot.setStorageValue(module, alias, value, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(module, snapshot)
        return liveModule.writeAndFlush(alias, value)
    end

    function moduleRegistry.snapshot.isDebugEnabled(entry, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        return liveModule.read("DebugMode") == true
    end

    function moduleRegistry.snapshot.setDebugEnabled(entry, value, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        liveModule.setDebugMode(value)
    end

    return moduleRegistry
end
