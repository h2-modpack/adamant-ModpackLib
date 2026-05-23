local MAX_UINT32 = 4294967295

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = deepCopy(child)
    end
    return copy
end

local function makeBitBinaryOp(predicate)
    return function(a, b)
        local result = 0
        local bitValue = 1
        a = a or 0
        b = b or 0

        while a > 0 or b > 0 do
            local abit = a % 2
            local bbit = b % 2
            if predicate(abit, bbit) then
                result = result + bitValue
            end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            bitValue = bitValue * 2
        end

        return result
    end
end

local function ensureBit32(env)
    env.bit32 = env.bit32 or bit32 or {
        band = makeBitBinaryOp(function(a, b)
            return a == 1 and b == 1
        end),
        bor = makeBitBinaryOp(function(a, b)
            return a == 1 or b == 1
        end),
        bnot = function(a)
            return MAX_UINT32 - (a or 0)
        end,
        lshift = function(a, n)
            return ((a or 0) * (2 ^ (n or 0))) % (2 ^ 32)
        end,
        rshift = function(a, n)
            return math.floor((a or 0) / (2 ^ (n or 0)))
        end,
    }
end

local function createModUtil()
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

local function createModUtilPlugin()
    return {
        globals = {},
        once_loaded = {
            game = function() end,
        },
    }
end

local function createRom(config, opts)
    local rom = opts.rom or {
        mods = {},
        game = {
            DeepCopyTable = deepCopy,
            SetupRunData = function() end,
        },
        ImGui = {},
        ImGuiCond = {
            FirstUseEver = 1,
        },
        ImGuiCol = {
            Text = 1,
        },
        gui = {
            add_to_menu_bar = function() end,
            add_imgui = function() end,
            add_always_draw_imgui = function() end,
            is_open = function()
                return false
            end,
        },
    }

    rom.mods = rom.mods or {}
    rom.game = rom.game or {}
    rom.game.DeepCopyTable = rom.game.DeepCopyTable or deepCopy
    rom.game.SetupRunData = rom.game.SetupRunData or function() end
    rom.game.CurrentRun = opts.CurrentRun
    rom.game.ScreenData = opts.ScreenData
    rom.game.HUDScreen = opts.HUDScreen
    rom.game.ShowingCombatUI = opts.ShowingCombatUI
    rom.game.ModifyTextBox = opts.ModifyTextBox
    rom.game.SetAlpha = opts.SetAlpha
    rom.game.CreateComponentFromData = opts.CreateComponentFromData
    rom.game.Destroy = opts.Destroy
    rom.ImGui = rom.ImGui or {}
    rom.ImGuiCond = rom.ImGuiCond or { FirstUseEver = 1 }
    rom.ImGuiCol = rom.ImGuiCol or { Text = 1 }
    rom.gui = rom.gui or {}
    rom.gui.add_to_menu_bar = rom.gui.add_to_menu_bar or function() end
    rom.gui.add_imgui = rom.gui.add_imgui or function() end
    rom.gui.add_always_draw_imgui = rom.gui.add_always_draw_imgui or function() end
    rom.gui.is_open = rom.gui.is_open or function()
        return false
    end

    rom.mods['SGG_Modding-ENVY'] = rom.mods['SGG_Modding-ENVY'] or {
        auto = function()
            return {}
        end,
    }
    rom.mods['SGG_Modding-Chalk'] = opts.chalk or rom.mods['SGG_Modding-Chalk'] or {
        auto = function()
            return config
        end,
        original = function(rawConfig)
            return deepCopy(rawConfig)
        end,
    }
    rom.mods['SGG_Modding-ModUtil'] = opts.modutilPlugin or rom.mods['SGG_Modding-ModUtil'] or createModUtilPlugin()
    rom.mods['SGG_Modding-ModUtil'].globals = rom.mods['SGG_Modding-ModUtil'].globals or rom.game

    return rom
end

local function buildHarnessImport(env, imports, importOverrides)
    return function(path, fenv, ...)
        local override = importOverrides[path]
        local result
        if override ~= nil then
            if type(override) == "function" then
                result = override(path, fenv, ...)
            else
                result = override
            end
        else
            local chunk = assert(loadfile("src/" .. path, "t", fenv or env))
            result = chunk(...)
        end

        if result ~= nil then
            imports[path] = result
        end
        return result
    end
end

local function createLibHarness(opts)
    opts = opts or {}

    local config = opts.config or { DebugMode = false }
    local public = opts.public or {}

    local runtimeRoot = opts.runtime or {}
    local plugin = opts.plugin or { guid = "test-module" }
    local rom = createRom(config, opts)
    local modUtilRuntime = opts.modutil or opts.modUtilRuntime or createModUtil()
    rom.mods['SGG_Modding-ModUtil'].globals.ModUtil = modUtilRuntime
    local imports = {}
    local importOverrides = opts.importOverrides or {}

    local env = setmetatable({
        public = public,
        rom = rom,
        ModUtil = modUtilRuntime,
        _PLUGIN = plugin,
        AdamantModpackLib_Runtime = runtimeRoot,
        ScreenData = opts.ScreenData,
        HUDScreen = opts.HUDScreen,
        ShowingCombatUI = opts.ShowingCombatUI,
        ModifyTextBox = opts.ModifyTextBox,
        SetAlpha = opts.SetAlpha,
        CreateComponentFromData = opts.CreateComponentFromData,
        Destroy = opts.Destroy,
        ImGuiComboFlags = opts.ImGuiComboFlags or { NoPreview = 64 },
        ImGuiCol = opts.ImGuiCol or rom.ImGuiCol,
        ImGuiTreeNodeFlags = opts.ImGuiTreeNodeFlags or {},
    }, {
        __index = _G,
    })
    env._G = env
    ensureBit32(env)
    env.import = buildHarnessImport(env, imports, importOverrides)

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
        game = rom.game,
        chalk = externals.chalk,
        modutil = env.ModUtil,
        modutilPlugin = externals.modutil,
        plugin = plugin,

        logging = imports["core/logging/logging.lua"],
        phaseGate = imports["core/module_bootstrap/ui/phase_gate.lua"],
        values = imports["core/helpers/values.lua"],
        gameDeps = externals.gameDeps or imports["core/game_deps/game_deps.lua"],
        cacheBundle = imports["core/cache/00_init.lua"],
        cache = imports["core/cache/00_init.lua"].service,
        hashingBundle = imports["core/hashing/hashing.lua"],
        hashing = imports["core/hashing/hashing.lua"].framework,
        storage = imports["core/storage/00_init.lua"],
        registry = imports["core/lib_bootstrap/registry.lua"],
        hostRegistry = imports["core/lib_bootstrap/host_registry.lua"],
        systemScope = imports["core/lib_bootstrap/system_scope.lua"],
        moduleState = imports["core/module_state/00_init.lua"],
        uiActions = imports["core/module_state/actions/ui_actions.lua"],
        coordinator = imports["core/coordinator/coordinator.lua"],
        integrationsBundle = imports["core/integrations/00_init.lua"],
        integrations = imports["core/integrations/00_init.lua"].service,
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
        authorHost = imports["core/module_bootstrap/author_host.lua"],
        hostLifecycle = imports["core/module_bootstrap/host_lifecycle.lua"],
        moduleHost = imports["core/module_bootstrap/host.lua"],
        moduleBundle = imports["core/module_bootstrap/module.lua"],
        fallbackUiBundle = imports["core/fallback/fallback_ui.lua"],
        fallbackUi = imports["core/fallback/fallback_ui.lua"].service,
    }
    harness.externals.gameDeps = harness.gameDeps
    function harness.createSystem(ownerId)
        return harness.systemScope.create(ownerId, {
            hooks = harness.hooksBundle.system,
            overlays = harness.overlaysBundle.system,
        })
    end

    return harness
end

return createLibHarness
