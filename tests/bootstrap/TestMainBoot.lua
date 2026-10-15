local lu = require("luaunit")
local fakeEngine = require("tests/harness/fake_engine")

TestMainBoot = {}

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
    local callbacks = fakeEngine.createCallbacks()
    local env = fakeEngine.createBaseEnv({
        callbacks = callbacks,
        public = public,
        config = config,
        _PLUGIN = { guid = "test-module" },
        plugin = { guid = "test-module" },
        runtimeRoot = {},
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
        ImGuiTreeNodeFlags = {},
        imports = imports,
        installImport = true,
        chalkOriginal = function(rawConfig)
            return rawConfig
        end,
        modUtilRuntime = opts.ModUtil,
    })

    assert(loadfile("src/main.lua", "t", env))()

    return {
        public = public,
        config = config,
        imports = imports,
        coordinator = imports["core/coordination/coordination.lua"],
        rom = env.rom,
        runtime = env.AdamantModpackLib_Runtime,
        menuCallbacks = callbacks.menuBar,
        imguiCallbacks = callbacks.imgui,
        alwaysDrawCallbacks = callbacks.alwaysDraw,
        onceLoadedCallbacks = callbacks.gameLoaded,
        chalkAutoPaths = callbacks.chalkAutoPaths,
        envyAutoCalls = callbacks.envyAutoCalls,
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
    lu.assertEquals(type(h.runtime.registry.ui), "table")
    lu.assertNil(h.runtime.coordinator)
    lu.assertEquals(h.imports["core/init.lua"].libWindow, h.imports["core/ui/lib_window.lua"])
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

function TestMainBoot.testMainUsesExpectedBootExternals()
    local h = createBootHarness()

    lu.assertEquals(h.envyAutoCalls, 1)
    lu.assertEquals(h.chalkAutoPaths, { "config.lua" })
    lu.assertEquals(#h.menuCallbacks, 1)
    -- The fallback GUI-close watcher and the shared hotkey tick.
    lu.assertEquals(#h.alwaysDrawCallbacks, 2)
    -- Lib's settings window.
    lu.assertEquals(#h.imguiCallbacks, 1)
    lu.assertEquals(#h.onceLoadedCallbacks, 1)
end

-- ImGui stub for the Lib menu and Lib settings window. `selectedTab` picks the tab whose
-- BeginTabItem returns true; `checkboxClicks` maps a checkbox label to the value it reports.
local function createLibUiImgui(opts)
    opts = opts or {}
    local calls = {
        beginMenu = 0,
        endMenu = 0,
        items = {},
        windows = {},
        tabs = {},
        checkboxes = {},
        colored = {},
        texts = {},
    }
    local clickItems = opts.clickItems or {}
    local checkboxClicks = opts.checkboxClicks or {}
    local function noop() end
    local imgui = {
        BeginMenu = function(label)
            calls.beginMenu = calls.beginMenu + 1
            calls.menuLabel = label
            return true
        end,
        EndMenu = function()
            calls.endMenu = calls.endMenu + 1
        end,
        MenuItem = function(label)
            calls.items[#calls.items + 1] = label
            if clickItems[label] then
                clickItems[label] = nil
                return true
            end
            return false
        end,
        Checkbox = function(label, current)
            calls.checkboxes[#calls.checkboxes + 1] = { label = label, current = current }
            local nextValue = checkboxClicks[label]
            if nextValue == nil then
                return current, false
            end
            return nextValue, true
        end,
        SetNextWindowSize = noop,
        Begin = function(title)
            calls.windows[#calls.windows + 1] = title
            return true, true
        end,
        End = noop,
        BeginTabBar = function()
            return true
        end,
        EndTabBar = noop,
        BeginTabItem = function(label)
            calls.tabs[#calls.tabs + 1] = label
            return label == (opts.selectedTab or "Hotkeys")
        end,
        EndTabItem = noop,
        PushStyleColor = noop,
        PopStyleColor = noop,
        TextColored = function(_, _, _, _, text)
            calls.colored[#calls.colored + 1] = text
        end,
        Text = function(text)
            calls.texts[#calls.texts + 1] = text
        end,
        Spacing = noop,
        Separator = noop,
        SameLine = noop,
        Button = function()
            return false
        end,
        AlignTextToFramePadding = noop,
        PushItemWidth = noop,
        PopItemWidth = noop,
        BeginCombo = function()
            return false
        end,
        IsItemHovered = function()
            return false
        end,
        SetTooltip = noop,
    }
    return imgui, calls
end

function TestMainBoot.testMainMenuHasOnlySettingsItemWithOrWithoutPacks()
    local h = createBootHarness()
    local imgui, calls = createLibUiImgui()
    h.rom.ImGui = imgui

    h.menuCallbacks[1]()
    h.coordinator.register("coordinated-pack", "Test Pack", { ModEnabled = true })
    h.menuCallbacks[1]()

    lu.assertEquals(calls.menuLabel, "adamant-lib")
    lu.assertEquals(calls.beginMenu, 2)
    lu.assertEquals(calls.items, { "Settings", "Settings" })
    lu.assertEquals(calls.checkboxes, {})
    lu.assertEquals(calls.endMenu, 2)
end

function TestMainBoot.testMainMenuSettingsOpensLibWindowWithHotkeysAndDebugTabs()
    local h = createBootHarness()
    local imgui, calls = createLibUiImgui({ clickItems = { Settings = true } })
    h.rom.ImGui = imgui

    h.imguiCallbacks[1]()
    lu.assertEquals(calls.windows, {})

    h.menuCallbacks[1]()
    h.imguiCallbacks[1]()
    lu.assertEquals(calls.windows, { "adamant-lib###adamant-lib" })
    lu.assertEquals(calls.tabs, { "Hotkeys", "Debug" })
    lu.assertEquals(calls.colored[1], "Hotkeys requested by every loaded module. Conflicts are listed first.")
    lu.assertEquals(calls.texts[1], "No module requests a hotkey.")
    -- The Hotkeys tab owns the reserved-key editor.
    lu.assertEquals(calls.colored[2], "Reserved keys")
    lu.assertEquals(calls.checkboxes, {})
end

function TestMainBoot.testLibWindowDebugTabTogglesLibConfig()
    local h = createBootHarness()
    local imgui, calls = createLibUiImgui({
        clickItems = { Settings = true },
        selectedTab = "Debug",
        checkboxClicks = {
            ["Lib Policy Debug"] = true,
            ["Config Backend Diagnostics"] = true,
        },
    })
    h.rom.ImGui = imgui

    h.menuCallbacks[1]()
    h.imguiCallbacks[1]()

    lu.assertEquals(calls.checkboxes, {
        { label = "Lib Policy Debug", current = false },
        { label = "Config Backend Diagnostics", current = false },
    })
    lu.assertTrue(h.config.DebugMode)
    lu.assertTrue(h.config.Diagnostics.configBackend.enabled)
    lu.assertEquals(calls.colored, {})
end
