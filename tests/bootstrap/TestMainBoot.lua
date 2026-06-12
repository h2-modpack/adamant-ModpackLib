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
    local config = {
        DebugMode = false,
        Diagnostics = {
            configBackend = {
                label = "Config Backend Diagnostics",
                enabled = false,
            },
        },
    }
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
        coordinator = imports["core/modpack/coordination.lua"],
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
    lu.assertEquals(type(h.public.modpack), "table")
    lu.assertEquals(type(h.public.modpack.registerCoordinator), "function")
    lu.assertEquals(type(h.public.modpack.createPack), "function")
    lu.assertEquals(type(h.public.modpack.createGuiCallbacks), "function")
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
    lu.assertEquals(type(h.runtime.registry.modpacks), "table")
    lu.assertEquals(type(h.runtime.registry.modpacks.packs), "table")
    lu.assertEquals(type(h.runtime.registry.modpacks.packList), "table")
    lu.assertNil(h.runtime.coordinator)
    lu.assertEquals(h.imports["core/init.lua"].modpackCoordination, h.imports["core/modpack/coordination.lua"])
end

function TestMainBoot.testMainLoadsModpackSubsystem()
    local h = createBootHarness()
    local rebuildReason

    lu.assertTrue(h.public.modpack.registerCoordinator("boot-pack", "Boot Pack", {
        ModEnabled = true,
    }, function(reason)
        rebuildReason = reason
        return true
    end))

    lu.assertTrue(h.coordinator.isRegistered("boot-pack"))
    lu.assertEquals(h.coordinator.getDisplayName("boot-pack"), "Boot Pack")
    lu.assertTrue(h.coordinator.requestRebuild("boot-pack", {
        reason = "test",
    }))
    lu.assertEquals(rebuildReason, {
        reason = "test",
    })

    local callbacks = h.public.modpack.createGuiCallbacks("boot-pack")
    lu.assertEquals(type(callbacks.render), "function")
    lu.assertEquals(type(callbacks.alwaysDraw), "function")
    lu.assertEquals(type(callbacks.menuBar), "function")
    callbacks.render()
    callbacks.alwaysDraw()
    callbacks.menuBar()
end

function TestMainBoot.testMainLoadsBeforeGlobalModUtilReady()
    local h = createBootHarness({
        withoutModUtil = true,
    })

    lu.assertEquals(type(h.public.createModule), "function")
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
        checkboxes = {},
    }
    h.rom.ImGui = {
        BeginMenu = function(label)
            calls.beginMenu = label
            return true
        end,
        Checkbox = function(label, current)
            calls.checkboxes[#calls.checkboxes + 1] = {
                label = label,
                current = current,
            }
            return true, true
        end,
        EndMenu = function()
            calls.endMenu = calls.endMenu + 1
        end,
    }

    h.menuCallbacks[1]()

    lu.assertEquals(calls.beginMenu, "adamant-lib")
    lu.assertEquals(calls.checkboxes[1], {
        label = "Lib Policy Debug",
        current = false,
    })
    lu.assertEquals(calls.checkboxes[2], {
        label = "Config Backend Diagnostics",
        current = false,
    })
    lu.assertEquals(calls.endMenu, 1)
    lu.assertTrue(h.config.DebugMode)
    lu.assertTrue(h.config.Diagnostics.configBackend.enabled)
end

function TestMainBoot.testMainDebugMenuHidesWhenCoordinatorIsRegistered()
    local h = createBootHarness()
    local beginMenuCalls = 0
    h.coordinator.register("coordinated-pack", "Test Pack", { ModEnabled = true })
    h.rom.ImGui = {
        BeginMenu = function()
            beginMenuCalls = beginMenuCalls + 1
            return true
        end,
    }

    h.menuCallbacks[1]()

    lu.assertEquals(beginMenuCalls, 0)
end
