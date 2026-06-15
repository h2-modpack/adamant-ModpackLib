local FakeEngine = {}

local MAX_UINT32 = 4294967295

local function append(list, value)
    list[#list + 1] = value
end

local function pathKey(path)
    if type(path) == "table" then
        return table.concat(path, ".")
    end
    return tostring(path)
end

local function pathSegments(path)
    if type(path) == "table" then
        return path
    end

    local segments = {}
    for segment in string.gmatch(tostring(path), "[^%.]+") do
        append(segments, segment)
    end
    return segments
end

local function resolvePathParent(root, path, createMissing)
    local segments = pathSegments(path)
    local node = root
    for index = 1, #segments - 1 do
        local segment = segments[index]
        if node[segment] == nil and createMissing then
            node[segment] = {}
        end
        node = node[segment]
        if type(node) ~= "table" then
            return nil, nil
        end
    end
    return node, segments[#segments]
end

local function readPath(root, path)
    local parent, key = resolvePathParent(root, path, false)
    if parent == nil then
        return nil
    end
    return parent[key]
end

local function writePath(root, path, value)
    local parent, key = resolvePathParent(root, path, true)
    if parent == nil or key == nil then
        return false
    end
    parent[key] = value
    return true
end

function FakeEngine.deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = FakeEngine.deepCopy(child)
    end
    return copy
end

function FakeEngine.makeBitBinaryOp(predicate)
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

function FakeEngine.createBit32()
    return {
        band = FakeEngine.makeBitBinaryOp(function(a, b)
            return a == 1 and b == 1
        end),
        bor = FakeEngine.makeBitBinaryOp(function(a, b)
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

function FakeEngine.installBit32(env)
    env.bit32 = env.bit32 or bit32 or FakeEngine.createBit32()
    return env.bit32
end

function FakeEngine.addFallback(env, fallback)
    local metatable = getmetatable(env)
    if metatable == nil then
        setmetatable(env, { __index = fallback })
    elseif metatable.__index == nil then
        metatable.__index = fallback
    end
    return env
end

function FakeEngine.makeColorTable()
    return setmetatable({
        Black = { 0, 0, 0, 255 },
    }, {
        __index = function(colors, key)
            local color = { 255, 255, 255, 255 }
            rawset(colors, key, color)
            return color
        end,
    })
end

function FakeEngine.makeImgui(overrides)
    return setmetatable(overrides or {}, {
        __index = function()
            return function()
                return false
            end
        end,
    })
end

function FakeEngine.defaultConfig()
    return {
        DebugMode = false,
        Diagnostics = {},
    }
end

function FakeEngine.createCallbacks()
    return {
        allModsLoaded = {},
        gameLoaded = {},
        imgui = {},
        alwaysDraw = {},
        menuBar = {},
        wraps = {},
        setupRunDataCount = 0,
        envyAutoCalls = 0,
        chalkAutoPaths = {},
        reloadLoads = {},
    }
end

function FakeEngine.createModUtilRuntime(callbacks, globals, opts)
    callbacks = callbacks or FakeEngine.createCallbacks()
    globals = globals or {}
    opts = opts or {}

    local mode = opts.modUtilWrapMode or "noop"
    local originals = {}
    local path = {}
    path.Context = {}

    function path.Wrap(name, handler)
        append(callbacks.wraps, { kind = "wrap", name = name, handler = handler })
        if mode ~= "functional" then
            return nil
        end

        local key = pathKey(name)
        local base = readPath(globals, name)
        if originals[key] == nil then
            originals[key] = base == nil and false or base
        end
        writePath(globals, name, function(...)
            return handler(base or function() end, ...)
        end)
        return nil
    end

    function path.Override(name, replacement)
        append(callbacks.wraps, { kind = "override", name = name, replacement = replacement })
        if mode ~= "functional" then
            return nil
        end

        local key = pathKey(name)
        if originals[key] == nil then
            local original = readPath(globals, name)
            originals[key] = original == nil and false or original
        end
        writePath(globals, name, replacement)
        return nil
    end

    function path.Restore(name)
        append(callbacks.wraps, { kind = "restore", name = name })
        if mode ~= "functional" then
            return nil
        end

        local original = originals[pathKey(name)]
        if original == false then
            writePath(globals, name, nil)
        elseif original ~= nil then
            writePath(globals, name, original)
        end
        return nil
    end

    function path.Context.Wrap(name, handler)
        append(callbacks.wraps, { kind = "contextWrap", name = name, handler = handler })
        return nil
    end

    return {
        Path = path,
    }
end

function FakeEngine.createModUtilPlugin(callbacks, globals, opts)
    callbacks = callbacks or FakeEngine.createCallbacks()
    opts = opts or {}
    globals = globals or {}

    local runtime = opts.runtime
    if runtime == nil and opts.installRuntime ~= false then
        runtime = FakeEngine.createModUtilRuntime(callbacks, globals, opts)
    end
    if runtime ~= nil and opts.installRuntime ~= false then
        globals.ModUtil = runtime
    end

    return {
        globals = globals,
        mod = runtime,
        once_loaded = {
            game = function(callback)
                append(callbacks.gameLoaded, callback)
            end,
        },
    }
end

function FakeEngine.createReloadPlugin(callbacks)
    callbacks = callbacks or FakeEngine.createCallbacks()
    return {
        auto_single = function()
            return {
                load = function(...)
                    local loaded = {}
                    for index = 1, select("#", ...) do
                        local callback = select(index, ...)
                        append(loaded, callback)
                        if type(callback) == "function" then
                            callback()
                        end
                    end
                    append(callbacks.reloadLoads, loaded)
                end,
            }
        end,
    }
end

function FakeEngine.createRom(opts)
    opts = opts or {}
    local callbacks = opts.callbacks or FakeEngine.createCallbacks()
    local config = opts.config or FakeEngine.defaultConfig()
    local rom = opts.rom or {}

    rom.mods = rom.mods or {}
    rom.mods.on_all_mods_loaded = rom.mods.on_all_mods_loaded or function(callback)
        append(callbacks.allModsLoaded, callback)
    end
    rom.game = rom.game or {}
    rom.game.Color = rom.game.Color or FakeEngine.makeColorTable()
    rom.game.DeepCopyTable = rom.game.DeepCopyTable or FakeEngine.deepCopy
    rom.game.SetupRunData = rom.game.SetupRunData or function()
        callbacks.setupRunDataCount = callbacks.setupRunDataCount + 1
    end

    local gameGlobals = {
        "CurrentRun",
        "ScreenData",
        "HUDScreen",
        "ShowingCombatUI",
        "ScreenCenterX",
        "ScreenHeight",
        "ModifyTextBox",
        "SetAlpha",
        "CreateComponentFromData",
        "Destroy",
    }
    for _, key in ipairs(gameGlobals) do
        if opts[key] ~= nil then
            rom.game[key] = opts[key]
        end
    end

    rom.ImGui = rom.ImGui or FakeEngine.makeImgui(opts.imgui)
    rom.ImGuiCond = rom.ImGuiCond or {
        FirstUseEver = 1,
    }
    rom.ImGuiCol = rom.ImGuiCol or {
        Text = 1,
        TextDisabled = 2,
        WindowBg = 3,
        ChildBg = 4,
        Header = 5,
        HeaderHovered = 6,
        HeaderActive = 7,
        Button = 8,
        ButtonHovered = 9,
        ButtonActive = 10,
        FrameBg = 11,
        FrameBgHovered = 12,
        FrameBgActive = 13,
        CheckMark = 14,
        Tab = 15,
        TabHovered = 16,
        TabActive = 17,
        Separator = 18,
        Border = 19,
        TitleBgActive = 20,
    }
    rom.gui = rom.gui or {}
    rom.gui.add_to_menu_bar = rom.gui.add_to_menu_bar or function(callback)
        append(callbacks.menuBar, callback)
    end
    rom.gui.add_imgui = rom.gui.add_imgui or function(callback)
        append(callbacks.imgui, callback)
    end
    rom.gui.add_always_draw_imgui = rom.gui.add_always_draw_imgui or function(callback)
        append(callbacks.alwaysDraw, callback)
    end
    rom.gui.is_open = rom.gui.is_open or function()
        return false
    end

    rom.mods["SGG_Modding-ENVY"] = opts.envy or rom.mods["SGG_Modding-ENVY"] or {
        auto = function()
            callbacks.envyAutoCalls = callbacks.envyAutoCalls + 1
            return opts.envyAutoResult or {}
        end,
    }
    rom.mods["SGG_Modding-Chalk"] = opts.chalk or rom.mods["SGG_Modding-Chalk"] or {
        auto = function(path)
            append(callbacks.chalkAutoPaths, path)
            if type(opts.chalkAuto) == "function" then
                return opts.chalkAuto(path, config)
            end
            return config
        end,
        original = opts.chalkOriginal or function(rawConfig)
            return FakeEngine.deepCopy(rawConfig)
        end,
    }

    local modUtilPlugin = opts.modutilPlugin or rom.mods["SGG_Modding-ModUtil"]
    local pluginGlobals = modUtilPlugin and modUtilPlugin.globals
    local modUtilRuntime = opts.modUtilRuntime
        or (pluginGlobals and pluginGlobals.ModUtil)
        or FakeEngine.createModUtilRuntime(callbacks, rom.game, opts)
    modUtilPlugin = modUtilPlugin
        or FakeEngine.createModUtilPlugin(callbacks, rom.game, {
            runtime = modUtilRuntime,
            installRuntime = true,
        })
    modUtilPlugin.globals = modUtilPlugin.globals or rom.game
    modUtilPlugin.globals.ModUtil = modUtilRuntime
    rom.mods["SGG_Modding-ModUtil"] = modUtilPlugin
    rom.game.ModUtil = modUtilRuntime

    if opts.withReload == true then
        rom.mods["SGG_Modding-ReLoad"] = opts.reload
            or rom.mods["SGG_Modding-ReLoad"]
            or FakeEngine.createReloadPlugin(callbacks)
    end

    return rom
end

function FakeEngine.buildImport(env, opts)
    opts = opts or {}
    local srcDir = opts.srcDir or "src"
    local imports = opts.imports or {}
    local importOverrides = opts.importOverrides or {}

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
            local chunkEnv = fenv or env
            if fenv then
                FakeEngine.addFallback(chunkEnv, env)
            end
            local chunk = assert(loadfile(srcDir .. "/" .. path, "t", chunkEnv))
            result = chunk(...)
        end

        if result ~= nil then
            imports[path] = result
        end
        return result
    end
end

function FakeEngine.createBaseEnv(opts)
    opts = opts or {}
    local callbacks = opts.callbacks or FakeEngine.createCallbacks()
    local rom = FakeEngine.createRom(FakeEngine.merge({
        callbacks = callbacks,
    }, opts))
    local modutil = rom.mods["SGG_Modding-ModUtil"]

    local env = FakeEngine.addFallback({
        _G = nil,
        public = opts.public,
        rom = rom,
        game = rom.game,
        modutil = modutil,
        ModUtil = rom.game.ModUtil,
        _PLUGIN = opts.plugin,
        AdamantModpackLib_Runtime = opts.runtimeRoot,
        ScreenData = opts.ScreenData or rom.game.ScreenData,
        HUDScreen = opts.HUDScreen or rom.game.HUDScreen,
        ShowingCombatUI = opts.ShowingCombatUI or rom.game.ShowingCombatUI,
        ScreenCenterX = opts.ScreenCenterX or rom.game.ScreenCenterX,
        ScreenHeight = opts.ScreenHeight or rom.game.ScreenHeight,
        ModifyTextBox = opts.ModifyTextBox or rom.game.ModifyTextBox,
        SetAlpha = opts.SetAlpha or rom.game.SetAlpha,
        CreateComponentFromData = opts.CreateComponentFromData or rom.game.CreateComponentFromData,
        Destroy = opts.Destroy or rom.game.Destroy,
        ImGuiComboFlags = opts.ImGuiComboFlags or { NoPreview = 64 },
        ImGuiCol = opts.ImGuiCol or rom.ImGuiCol,
        ImGuiTreeNodeFlags = opts.ImGuiTreeNodeFlags or {},
    }, opts.fallback or _G)
    env._G = env
    FakeEngine.installBit32(env)

    if opts.installImport == true then
        env.import = FakeEngine.buildImport(env, {
            srcDir = opts.srcDir or "src",
            imports = opts.imports,
            importOverrides = opts.importOverrides,
        })
    end

    return env, callbacks
end

function FakeEngine.merge(base, overrides)
    local merged = {}
    for key, value in pairs(base or {}) do
        merged[key] = value
    end
    for key, value in pairs(overrides or {}) do
        merged[key] = value
    end
    return merged
end

function FakeEngine.loadPlugin(baseEnv, guid, srcDir, opts)
    opts = opts or {}
    local env = FakeEngine.addFallback({
        _G = nil,
        _PLUGIN = opts.plugin or { guid = guid },
        public = opts.public or {},
        rom = baseEnv.rom,
        game = baseEnv.game or baseEnv.rom.game,
        modutil = baseEnv.modutil,
        ModUtil = baseEnv.ModUtil,
    }, baseEnv)
    env._G = env
    FakeEngine.installBit32(env)

    env.import_as_fallback = function(source)
        if type(source) ~= "table" then
            return
        end
        for key, value in pairs(source) do
            if env[key] == nil then
                env[key] = value
            end
        end
    end

    env.import = FakeEngine.buildImport(env, {
        srcDir = srcDir,
        imports = opts.imports,
        importOverrides = opts.importOverrides,
    })

    local mainPath = opts.mainPath or (srcDir .. "/main.lua")
    local chunk = assert(loadfile(mainPath, "t", env))
    chunk()

    if opts.register ~= false then
        baseEnv.rom.mods[guid] = env.public
    end
    return env
end

function FakeEngine.runCallbacks(callbacks, key, label)
    for index, callback in ipairs(callbacks[key] or {}) do
        local ok, err = xpcall(callback, debug.traceback)
        if not ok then
            error(string.format("%s callback %d failed: %s", label or key, index, tostring(err)), 2)
        end
    end
end

function FakeEngine.runGameLoaded(callbacks)
    FakeEngine.runCallbacks(callbacks, "gameLoaded", "once_loaded.game")
end

function FakeEngine.runAllModsLoaded(callbacks)
    FakeEngine.runCallbacks(callbacks, "allModsLoaded", "on_all_mods_loaded")
end

function FakeEngine.runAlwaysDraw(callbacks)
    FakeEngine.runCallbacks(callbacks, "alwaysDraw", "always_draw_imgui")
end

return FakeEngine
