local lu = require("luaunit")

TestMainBoot = {}

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
    env.bit32 = bit32 or {
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

local function createBootHarness(opts)
    opts = opts or {}
    local public = {}
    local config = { DebugMode = false }
    local imports = {}
    local menuCallbacks = {}
    local imguiCallbacks = {}
    local alwaysDrawCallbacks = {}
    local onceLoadedCallbacks = {}
    local chalkAutoPaths = {}
    local envyAutoCalls = 0

    local rom = {
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
            add_to_menu_bar = function(callback)
                menuCallbacks[#menuCallbacks + 1] = callback
            end,
            add_imgui = function(callback)
                imguiCallbacks[#imguiCallbacks + 1] = callback
            end,
            add_always_draw_imgui = function(callback)
                alwaysDrawCallbacks[#alwaysDrawCallbacks + 1] = callback
            end,
            is_open = function()
                return false
            end,
        },
    }

    rom.mods['SGG_Modding-ENVY'] = {
        auto = function()
            envyAutoCalls = envyAutoCalls + 1
            return {}
        end,
    }
    rom.mods['SGG_Modding-Chalk'] = {
        auto = function(path)
            chalkAutoPaths[#chalkAutoPaths + 1] = path
            return config
        end,
        original = function(rawConfig)
            return rawConfig
        end,
    }
    rom.mods['SGG_Modding-ModUtil'] = {
        globals = rom.game,
        once_loaded = {
            game = function(callback)
                onceLoadedCallbacks[#onceLoadedCallbacks + 1] = callback
            end,
        },
    }

    local modUtilCore = opts.ModUtil
    if modUtilCore == nil and opts.withoutModUtil ~= true then
        modUtilCore = {
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
    rom.game.ModUtil = modUtilCore

    local env = setmetatable({
        public = public,
        rom = rom,
        _PLUGIN = { guid = "test-module" },
        AdamantModpackLib_Runtime = {},
        ScreenData = {
            HUD = {
                ComponentData = {},
            },
        },
        HUDScreen = {
            Components = {},
        },
        ShowingCombatUI = true,
        ModifyTextBox = function() end,
        SetAlpha = function() end,
        CreateComponentFromData = function(_, data)
            return {
                Id = data.Name,
                Name = data.Name,
            }
        end,
        Destroy = function() end,
        ImGuiComboFlags = {
            NoPreview = 64,
        },
        ImGuiCol = rom.ImGuiCol,
        ImGuiTreeNodeFlags = {},
    }, {
        __index = _G,
    })
    env._G = env
    ensureBit32(env)

    env.import = function(path, fenv, ...)
        local chunk = assert(loadfile("src/" .. path, "t", fenv or env))
        local result = chunk(...)
        if result ~= nil then
            imports[path] = result
        end
        return result
    end

    assert(loadfile("src/main.lua", "t", env))()

    return {
        public = public,
        config = config,
        imports = imports,
        coordinator = imports["core/coordinator/coordinator.lua"],
        rom = rom,
        runtime = env.AdamantModpackLib_Runtime,
        menuCallbacks = menuCallbacks,
        imguiCallbacks = imguiCallbacks,
        alwaysDrawCallbacks = alwaysDrawCallbacks,
        onceLoadedCallbacks = onceLoadedCallbacks,
        chalkAutoPaths = chalkAutoPaths,
        envyAutoCalls = envyAutoCalls,
    }
end

function TestMainBoot.testMainLoadsPublicSurface()
    local h = createBootHarness()

    lu.assertNil(h.public.config)
    lu.assertNil(h.public.resetStorageToDefaults)
    lu.assertEquals(type(h.public.createModule), "function")
    lu.assertNil(h.public.tryCreateModule)
    lu.assertNil(h.public.createSystem)
    lu.assertEquals(type(h.public.createFrameworkRuntime), "function")
    lu.assertNil(h.public.getLiveModuleHost)

    lu.assertNil(h.public.coordinator)
    lu.assertNil(h.public.cache)
    lu.assertNil(h.public.hashing)
    lu.assertNil(h.public.hooks)
    lu.assertNil(h.public.shared)
    lu.assertNil(h.public.mutation)
    lu.assertNil(h.public.overlays)
    lu.assertNil(h.public.widgets)
    lu.assertNil(h.public.nav)
    lu.assertNil(h.public.imguiHelpers)

    lu.assertEquals(type(h.runtime.registry), "table")
    lu.assertEquals(type(h.runtime.registry.modules), "table")
    lu.assertEquals(type(h.runtime.registry.hooks), "table")
    lu.assertEquals(type(h.runtime.registry.overlays), "table")
    lu.assertEquals(type(h.runtime.registry.fallback), "table")
    lu.assertEquals(type(h.runtime.registry.coordinators), "table")
    lu.assertNil(h.runtime.coordinator)
    lu.assertEquals(h.imports["core/init.lua"].coordinator, h.imports["core/coordinator/coordinator.lua"])
end

function TestMainBoot.testMainLoadsBeforeGlobalModUtilReady()
    local h = createBootHarness({
        withoutModUtil = true,
    })

    lu.assertEquals(type(h.public.createModule), "function")
    lu.assertEquals(type(h.public.createFrameworkRuntime), "function")
end

function TestMainBoot.testMainCreatesFrameworkRuntimeFacade()
    local h = createBootHarness()
    local frameworkRuntime = h.public.createFrameworkRuntime("adamant-ModpackFramework")

    lu.assertNil(frameworkRuntime.getOwnerId)
    lu.assertEquals(type(frameworkRuntime.diagnostics), "table")
    lu.assertEquals(type(frameworkRuntime.diagnostics.isLibDebugEnabled), "function")
    lu.assertEquals(type(frameworkRuntime.diagnostics.setLibDebugEnabled), "function")
    lu.assertEquals(type(frameworkRuntime.coordinator), "table")
    lu.assertEquals(type(frameworkRuntime.coordinator.register), "function")
    lu.assertEquals(type(frameworkRuntime.coordinator.registerRebuild), "function")
    lu.assertEquals(type(frameworkRuntime.coordinator.isRegistered), "function")
    lu.assertEquals(type(frameworkRuntime.overlays), "table")
    lu.assertEquals(type(frameworkRuntime.overlays.order), "table")
    lu.assertEquals(type(frameworkRuntime.overlays.define), "function")
    lu.assertEquals(type(frameworkRuntime.modules), "table")
    lu.assertEquals(type(frameworkRuntime.modules.getLiveHost), "function")
    lu.assertEquals(type(frameworkRuntime.hashing), "table")
    lu.assertEquals(type(frameworkRuntime.hashing.getRoots), "function")
    lu.assertEquals(type(frameworkRuntime.hashing.toHash), "function")
    lu.assertEquals(type(frameworkRuntime.ui.suppressOverlays), "function")
    lu.assertEquals(type(frameworkRuntime.ui.areOverlaysSuppressed), "function")

    lu.assertFalse(frameworkRuntime.ui.areOverlaysSuppressed())
    local token = frameworkRuntime.ui.suppressOverlays()
    lu.assertTrue(frameworkRuntime.ui.areOverlaysSuppressed())
    token.release()
    lu.assertFalse(frameworkRuntime.ui.areOverlaysSuppressed())

    lu.assertFalse(frameworkRuntime.diagnostics.isLibDebugEnabled())
    frameworkRuntime.diagnostics.setLibDebugEnabled(true)
    lu.assertTrue(h.config.DebugMode)
    lu.assertTrue(frameworkRuntime.diagnostics.isLibDebugEnabled())
    frameworkRuntime.diagnostics.setLibDebugEnabled(false)
    lu.assertFalse(h.config.DebugMode)
    lu.assertNil(frameworkRuntime.modules.getLiveHost(""))
end

function TestMainBoot.testMainFrameworkRuntimeRejectsInvalidLibDebugMode()
    local h = createBootHarness()
    local frameworkRuntime = h.public.createFrameworkRuntime("adamant-ModpackFramework")

    lu.assertErrorMsgContains("frameworkRuntime.diagnostics.setLibDebugEnabled: enabled must be a boolean", function()
        frameworkRuntime.diagnostics.setLibDebugEnabled("true")
    end)
end

function TestMainBoot.testMainFrameworkRuntimeRejectsInvalidOverlayScope()
    local h = createBootHarness()
    local frameworkRuntime = h.public.createFrameworkRuntime("adamant-ModpackFramework")

    lu.assertErrorMsgContains("frameworkRuntime.overlays.define: packId must be a non-empty string", function()
        frameworkRuntime.overlays.define("", "hud", function() end)
    end)
    lu.assertErrorMsgContains("frameworkRuntime.overlays.define: name must be a non-empty string", function()
        frameworkRuntime.overlays.define("test", "", function() end)
    end)
    lu.assertErrorMsgContains("frameworkRuntime.overlays.define: register must be a function", function()
        frameworkRuntime.overlays.define("test", "hud", true)
    end)
end

function TestMainBoot.testMainFrameworkRuntimeRejectsInvalidCaller()
    local h = createBootHarness()

    lu.assertErrorMsgContains("createFrameworkRuntime: frameworkPluginGuid must be adamant-ModpackFramework", function()
        h.public.createFrameworkRuntime("test-module")
    end)
    lu.assertErrorMsgContains("createFrameworkRuntime: packId is not accepted", function()
        h.public.createFrameworkRuntime("adamant-ModpackFramework", "test")
    end)
end

function TestMainBoot.testMainUsesExpectedBootExternals()
    local h = createBootHarness()

    lu.assertEquals(h.envyAutoCalls, 1)
    lu.assertEquals(h.chalkAutoPaths, { "config.lua" })
    lu.assertEquals(#h.menuCallbacks, 1)
    lu.assertEquals(#h.alwaysDrawCallbacks, 1)
    lu.assertEquals(#h.onceLoadedCallbacks, 1)
end

function TestMainBoot.testMainDebugMenuTogglesLibConfig()
    local h = createBootHarness()
    local calls = {
        endMenu = 0,
    }
    h.rom.ImGui = {
        BeginMenu = function(label)
            calls.beginMenu = label
            return true
        end,
        Checkbox = function(label, current)
            calls.checkbox = {
                label = label,
                current = current,
            }
            return true, true
        end,
        IsItemHovered = function()
            return true
        end,
        SetTooltip = function(text)
            calls.tooltip = text
        end,
        EndMenu = function()
            calls.endMenu = calls.endMenu + 1
        end,
    }

    h.menuCallbacks[1]()

    lu.assertEquals(calls.beginMenu, "adamant-lib")
    lu.assertEquals(calls.checkbox, {
        label = "Lib Debug",
        current = false,
    })
    lu.assertEquals(calls.endMenu, 1)
    lu.assertStrContains(calls.tooltip, "Print lib-internal diagnostic warnings")
    lu.assertTrue(h.config.DebugMode)
end

function TestMainBoot.testMainDebugMenuHidesWhenCoordinatorIsRegistered()
    local h = createBootHarness()
    local beginMenuCalls = 0
    h.coordinator.register("coordinated-pack", { ModEnabled = true })
    h.rom.ImGui = {
        BeginMenu = function()
            beginMenuCalls = beginMenuCalls + 1
            return true
        end,
    }

    h.menuCallbacks[1]()

    lu.assertEquals(beginMenuCalls, 0)
end
