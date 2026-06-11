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

local function formatConfigValue(value)
    if type(value) == "boolean" then
        return value and "true" or "false"
    elseif type(value) == "number" then
        return tostring(value)
    end
    value = tostring(value or "")
    value = string.gsub(value, "\\", "\\\\")
    value = string.gsub(value, '"', '\\"')
    value = string.gsub(value, "\n", "\\n")
    return '"' .. value .. '"'
end

local function combinePath(left, right)
    if string.sub(left, -1) == "/" then
        return left .. right
    end
    return left .. "/" .. right
end

local function configureNativeConfigRoot(rom, root)
    os.execute('mkdir -p "' .. root .. '"')
    rom.paths = rom.paths or {}
    rom.path = rom.path or {}
    rom.paths.config = function()
        return root
    end
    rom.path.combine = combinePath
end

local function writeNativeConfig(root, pluginGuid, values)
    local file = assert(io.open(combinePath(root, pluginGuid .. ".cfg"), "w"))
    file:write("## Settings file was created by plugin adamant-ModpackLib test harness\n\n")
    file:write("[config]\n\n")
    for key, value in pairs(values or {}) do
        if type(value) ~= "table" then
            file:write(tostring(key), " = ", formatConfigValue(value), "\n")
        end
    end
    for key, value in pairs(values or {}) do
        if type(value) == "table" then
            file:write("\n[config.", tostring(key), "]\n\n")
            file:write("_RowCount = ", tostring(#value), "\n")
            for rowIndex, row in ipairs(value) do
                file:write("\n[config.", tostring(key), ".", tostring(rowIndex), "]\n\n")
                for cellKey, cellValue in pairs(row or {}) do
                    if type(cellValue) ~= "table" then
                        file:write(tostring(cellKey), " = ", formatConfigValue(cellValue), "\n")
                    end
                end
            end
        end
    end
    file:close()
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function unescapeString(value)
    value = string.gsub(value, "\\n", "\n")
    value = string.gsub(value, '\\"', '"')
    value = string.gsub(value, "\\\\", "\\")
    return value
end

local function parseConfigValue(rawValue)
    rawValue = trim(rawValue)
    if rawValue == "" then
        return ""
    end

    local first = string.sub(rawValue, 1, 1)
    local last = string.sub(rawValue, -1)
    if first == '"' and last == '"' and #rawValue >= 2 then
        return unescapeString(string.sub(rawValue, 2, -2))
    end

    local lower = string.lower(rawValue)
    if lower == "true" then
        return true
    elseif lower == "false" then
        return false
    end

    local numberValue = tonumber(rawValue)
    if numberValue ~= nil then
        return numberValue
    end

    return rawValue
end

local function parseNativeConfig(path)
    local result = {}
    local file = io.open(path, "r")
    if not file then
        return result
    end

    local currentSection = "config"
    for line in file:lines() do
        local section = string.match(line, "^%s*%[([^%]]+)%]%s*$")
        if section then
            currentSection = trim(section)
        elseif not string.match(line, "^%s*[#;]") then
            local key, rawValue = string.match(line, "^%s*([^=]-)%s*=%s*(.-)%s*$")
            key = key and trim(key) or nil
            if key and key ~= "" then
                local value = parseConfigValue(rawValue)
                if currentSection == "config" then
                    result[key] = value
                else
                    local tableKey, rowIndex = string.match(currentSection, "^config%.([^%.]+)%.(%d+)$")
                    if tableKey and key ~= "_RowCount" then
                        result[tableKey] = result[tableKey] or {}
                        result[tableKey][tonumber(rowIndex)] = result[tableKey][tonumber(rowIndex)] or {}
                        result[tableKey][tonumber(rowIndex)][key] = value
                    end
                end
            end
        end
    end
    file:close()

    return result
end

local function installConfigProxy(config, path)
    if type(config) ~= "table" then
        return
    end

    local snapshot = deepCopy(config)
    for key in pairs(config) do
        config[key] = nil
    end

    local function readSnapshot()
        return parseNativeConfig(path)
    end

    local function writeSnapshot(snapshotValue)
        local dir, fileName = string.match(path, "^(.*)/([^/]+)$")
        local pluginGuid = fileName and string.gsub(fileName, "%.cfg$", "") or "test-module"
        writeNativeConfig(dir or ".", pluginGuid, snapshotValue)
    end

    setmetatable(config, {
        __index = function(_, key)
            return readSnapshot()[key]
        end,
        __newindex = function(_, key, value)
            local current = readSnapshot()
            current[key] = value
            writeSnapshot(current)
        end,
        __pairs = function()
            return pairs(readSnapshot())
        end,
        __len = function()
            return #readSnapshot()
        end,
    })

    writeSnapshot(snapshot)
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
    local nativeConfigRoot = opts.nativeConfigRoot
        or ("/tmp/adamant-modpacklib-tests-" .. tostring(os.clock()):gsub("[^%d]", ""))
    configureNativeConfigRoot(rom, nativeConfigRoot)
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
        hashingBundle = imports["core/hashing/hashing.lua"],
        hashing = imports["core/hashing/hashing.lua"].framework,
        storage = imports["core/storage/00_init.lua"],
        registry = imports["core/lib_bootstrap/registry.lua"],
        moduleRegistry = imports["core/lib_bootstrap/module_registry.lua"],
        systemScope = imports["core/lib_bootstrap/system_scope.lua"],
        moduleState = imports["core/module_state/00_init.lua"],
        uiActions = imports["core/module_state/actions/ui_actions.lua"],
        coordinator = imports["core/coordinator/coordinator.lua"],
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
        writeNativeConfig(self.nativeConfigRoot, pluginGuid, values)
    end
    function harness:readNativeConfig(pluginGuid)
        local file = assert(io.open(combinePath(self.nativeConfigRoot, pluginGuid .. ".cfg"), "r"))
        local contents = file:read("*a")
        file:close()
        return contents
    end
    function harness:createConfigFixture(config, pluginGuid)
        config = config or {}
        pluginGuid = pluginGuid or ("test-module-state-" .. tostring(os.clock()):gsub("[^%d]", ""))
        local path = combinePath(self.nativeConfigRoot, pluginGuid .. ".cfg")
        writeNativeConfig(self.nativeConfigRoot, pluginGuid, config)
        installConfigProxy(config, path)
        return path
    end
    function harness:createModuleState(config, definition, opts)
        opts = opts or {}
        local configPath = opts.configPath or self:createConfigFixture(config or {}, opts.pluginGuid)
        local createOpts = {}
        for key, value in pairs(opts) do
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
