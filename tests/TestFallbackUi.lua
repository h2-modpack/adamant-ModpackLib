local lu = require("luaunit")
local createFallbackUiHarness = require("tests/harness/create_fallback_ui_harness")

TestFallbackUi = {}

local PLUGIN_GUID = "test-fallback-ui-module"

local function makeHost(opts)
    opts = opts or {}
    local calls = {
        setEnabled = {},
        setDebugMode = {},
        resync = 0,
        drawTab = 0,
        commitIfDirty = 0,
    }
    local enabled = opts.enabled ~= false
    local debugMode = opts.debugMode == true
    local host = {
        calls = calls,
        getOwnerId = function()
            return opts.pluginGuid or PLUGIN_GUID
        end,
        getModuleId = function()
            return opts.id or "FallbackUiTest"
        end,
        getPackId = function()
            return opts.modpack
        end,
        getMeta = function()
            return {
                name = opts.name or "Fallback UI Test",
            }
        end,
        affectsRunData = function()
            return opts.affectsRunData == true
        end,
        read = function(alias)
            if alias == "Enabled" then
                return enabled
            elseif alias == "DebugMode" then
                return debugMode
            end
            return nil
        end,
        isEnabled = function()
            return enabled
        end,
        setEnabled = function(value)
            calls.setEnabled[#calls.setEnabled + 1] = value
            if opts.setEnabledFails then
                return false, "enable boom"
            end
            enabled = value == true
            return true, nil
        end,
        setDebugMode = function(value)
            calls.setDebugMode[#calls.setDebugMode + 1] = value
            debugMode = value == true
        end,
        resync = function()
            calls.resync = calls.resync + 1
        end,
        drawTab = function()
            calls.drawTab = calls.drawTab + 1
        end,
        commitIfDirty = function()
            calls.commitIfDirty = calls.commitIfDirty + 1
            return true, nil, opts.committed == true
        end,
        drawTabAndCommit = function()
            calls.drawTab = calls.drawTab + 1
            calls.commitIfDirty = calls.commitIfDirty + 1
            if opts.drawTabAndCommitThrows then
                error("draw tab boom")
            end
            return true, nil, opts.committed == true
        end,
    }
    return host
end

local function makeImgui(opts)
    opts = opts or {}
    local calls = {
        setNextWindowSize = 0,
        begin = 0,
        endWindow = 0,
        beginMenu = 0,
        endMenu = 0,
        separator = 0,
        spacing = 0,
        checkboxLabels = {},
        buttons = {},
    }
    local checkboxValues = opts.checkboxValues or {}
    local buttonClicks = opts.buttonClicks or {}
    local imgui = {
        calls = calls,
        SetNextWindowSize = function(width, height, cond)
            calls.setNextWindowSize = calls.setNextWindowSize + 1
            calls.windowSize = { width = width, height = height, cond = cond }
        end,
        Begin = function(title, showWindow)
            calls.begin = calls.begin + 1
            calls.title = title
            calls.showWindow = showWindow
            return opts.open ~= false, opts.shouldDraw ~= false
        end,
        End = function()
            calls.endWindow = calls.endWindow + 1
        end,
        Checkbox = function(label, current)
            calls.checkboxLabels[#calls.checkboxLabels + 1] = label
            local nextValue = checkboxValues[label]
            if nextValue == nil then
                return current, false
            end
            return nextValue, true
        end,
        Button = function(label)
            calls.buttons[#calls.buttons + 1] = label
            return buttonClicks[label] == true
        end,
        Separator = function()
            calls.separator = calls.separator + 1
        end,
        Spacing = function()
            calls.spacing = calls.spacing + 1
        end,
        BeginMenu = function(label)
            calls.beginMenu = calls.beginMenu + 1
            calls.menuLabel = label
            return opts.menuOpen ~= false
        end,
        MenuItem = function(label)
            calls.menuItem = label
            return opts.menuClicked == true
        end,
        EndMenu = function()
            calls.endMenu = calls.endMenu + 1
        end,
    }
    return imgui, calls
end

local function createBridge(h, pluginGuid)
    local bridge = nil
    local host = h:createLibModule(pluginGuid or PLUGIN_GUID)
    h.fallbackUi.attachGuiOnce(host, function(ui)
        bridge = ui
    end)
    return bridge
end

function TestFallbackUi:setUp()
    self.h = createFallbackUiHarness()
    self.h:captureWarnings()
end

function TestFallbackUi:tearDown()
    self.h:restoreWarnings()
end

function TestFallbackUi:testAttachGuiOnceRequiresManagedHost()
    lu.assertErrorMsgContains("expected managed module", function()
        self.h.fallbackUi.attachGuiOnce(nil, function() end)
    end)
end

function TestFallbackUi:testAttachGuiOnceRequiresRegisterCallback()
    local host = self.h:createLibModule(PLUGIN_GUID)
    lu.assertErrorMsgContains("register must be a function", function()
        self.h.fallbackUi.attachGuiOnce(host)
    end)
end

function TestFallbackUi:testBridgeCallbacksNoOpBeforeRuntimeExists()
    local bridge = nil
    local host = self.h:createLibModule(PLUGIN_GUID)
    self.h.fallbackUi.attachGuiOnce(host, function(ui)
        bridge = ui
    end)

    local okMenu, errMenu = pcall(bridge.addMenuBar)
    local okRender, errRender = pcall(bridge.renderWindow)
    local okClosed, errClosed = pcall(bridge.handleGuiClosed)

    lu.assertTrue(okMenu, errMenu)
    lu.assertTrue(okRender, errRender)
    lu.assertTrue(okClosed, errClosed)
end

function TestFallbackUi:testCreatesRuntimeWhenModuleIsNotCoordinated()
    local host = makeHost({ modpack = "fallback-pack" })
    self.h.coordinator.register("fallback-pack", nil)

    local runtime = self.h:installFallbackRuntime(host)

    lu.assertEquals(type(runtime.renderWindow), "function")
    lu.assertEquals(type(runtime.addMenuBar), "function")
    lu.assertEquals(type(runtime.handleGuiClosed), "function")
end

function TestFallbackUi:testBridgeDispatchesInstalledRuntime()
    local bridge = createBridge(self.h)
    local host = makeHost({ modpack = "fallback-pack" })
    self.h.coordinator.register("fallback-pack", nil)
    local imgui = makeImgui({ menuClicked = true })
    self.h.rom.ImGui = imgui

    self.h:installFallbackRuntime(host)
    bridge.addMenuBar()
    bridge.renderWindow()

    lu.assertEquals(host.calls.drawTab, 1)
end

function TestFallbackUi:testDisabledFallbackRuntimeCollapsesModuleBody()
    local bridge = createBridge(self.h)
    local host = makeHost({ modpack = "fallback-pack", enabled = false })
    self.h.coordinator.register("fallback-pack", nil)
    local imgui, calls = makeImgui({ menuClicked = true })
    self.h.rom.ImGui = imgui

    self.h:installFallbackRuntime(host)
    bridge.addMenuBar()
    bridge.renderWindow()

    lu.assertEquals(calls.checkboxLabels, { "Enabled", "Debug Mode" })
    lu.assertEquals(host.calls.drawTab, 0)
    lu.assertEquals(host.calls.commitIfDirty, 0)
end

function TestFallbackUi:testEnablingFallbackRuntimeOpensModuleBodyInSameFrame()
    local bridge = createBridge(self.h)
    local host = makeHost({ modpack = "fallback-pack", enabled = false })
    self.h.coordinator.register("fallback-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        checkboxValues = {
            Enabled = true,
        },
    })
    self.h.rom.ImGui = imgui

    self.h:installFallbackRuntime(host)
    bridge.addMenuBar()
    bridge.renderWindow()

    lu.assertEquals(host.calls.setEnabled, { true })
    lu.assertEquals(host.calls.drawTab, 1)
    lu.assertEquals(host.calls.commitIfDirty, 1)
end

function TestFallbackUi:testBridgeDispatchesReplacementRuntime()
    local bridge = createBridge(self.h)
    local firstHost = makeHost({ modpack = "fallback-pack", name = "First Fallback UI" })
    self.h.coordinator.register("fallback-pack", nil)
    self.h.rom.ImGui = makeImgui({ menuClicked = true })
    self.h:installFallbackRuntime(firstHost)
    bridge.addMenuBar()
    bridge.renderWindow()

    local secondHost = makeHost({ modpack = "fallback-pack", name = "Second Fallback UI" })
    self.h.rom.ImGui = makeImgui({ menuClicked = true })
    self.h:installFallbackRuntime(secondHost)
    bridge.addMenuBar()
    bridge.renderWindow()

    lu.assertEquals(firstHost.calls.drawTab, 1)
    lu.assertEquals(secondHost.calls.drawTab, 1)
end

function TestFallbackUi:testFallbackRuntimeReplacementClosesPreviousRuntime()
    local firstHost = makeHost({ modpack = "fallback-pack", name = "First Fallback UI" })
    self.h.coordinator.register("fallback-pack", nil)
    self.h.rom.ImGui = makeImgui({ menuClicked = true })
    local firstRuntime = self.h:installFallbackRuntime(firstHost)
    firstRuntime.addMenuBar()

    lu.assertEquals(self.h:countUiSuppressors(), 1)

    local secondHost = makeHost({ modpack = "fallback-pack", name = "Second Fallback UI" })
    self.h:installFallbackRuntime(secondHost)

    lu.assertEquals(self.h:countUiSuppressors(), 0)
end

function TestFallbackUi:testFallbackRuntimeRollbackRestoresPreviousRuntime()
    local firstHost = makeHost({ modpack = "fallback-pack", name = "First Fallback UI" })
    local secondHost = makeHost({ modpack = "fallback-pack", name = "Second Fallback UI" })
    self.h.coordinator.register("fallback-pack", nil)

    local firstRuntime = self.h:installFallbackRuntime(firstHost)
    local secondReceipt = self.h.fallbackUi.installForModule(secondHost)

    lu.assertTrue(secondReceipt.commit())
    lu.assertNotEquals(self.h:getFallbackUiRuntime(PLUGIN_GUID), firstRuntime)

    lu.assertTrue(secondReceipt.dispose())

    lu.assertEquals(self.h:getFallbackUiRuntime(PLUGIN_GUID), firstRuntime)
end

function TestFallbackUi:testFallbackRuntimeIsRetiredWithOwningHost()
    local pluginGuid = "test-fallback-ui-retired-with-host"
    self.h.coordinator.register("fallback-pack", nil)

    local firstHost = self.h:createActivatedLibModule(pluginGuid, {
        id = "FallbackUiRuntimeRetire",
        name = "Fallback UI Runtime Retire",
        attachFallbackUi = true,
    })
    local firstRuntime = self.h:getFallbackUiRuntime(pluginGuid)
    local secondHost = self.h:createActivatedLibModule(pluginGuid, {
        id = "FallbackUiRuntimeRetire",
        name = "Fallback UI Runtime Retire",
        attachFallbackUi = true,
    })

    lu.assertNotEquals(firstHost, secondHost)
    lu.assertNotNil(self.h:getFallbackUiRuntime(pluginGuid))
    lu.assertNotEquals(self.h:getFallbackUiRuntime(pluginGuid), firstRuntime)
end

function TestFallbackUi:testSkipsFallbackUiLifecycleWhenCoordinated()
    local host = makeHost({ modpack = "fallback-pack" })
    self.h.coordinator.register("fallback-pack", { ModEnabled = true })
    local imgui, calls = makeImgui({ menuClicked = true })
    self.h.rom.ImGui = imgui

    local runtime = self.h:installFallbackRuntime(host)
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(calls.beginMenu, 0)
    lu.assertEquals(calls.begin, 0)
end

function TestFallbackUi:testFallbackMarkerHidesWhenOnlyFallbackRuntimeIsCoordinated()
    local host = makeHost({ modpack = "fallback-pack" })
    self.h.coordinator.register("fallback-pack", { ModEnabled = true })

    self.h:installFallbackRuntime(host)
    local row = self.h:getFallbackMarkerRow()

    lu.assertNotNil(row)
    lu.assertFalse(row.visible())
end

function TestFallbackUi:testFallbackMarkerShowsWhenFallbackRuntimeIsUncoordinated()
    local host = makeHost({ modpack = "fallback-pack" })
    self.h.coordinator.register("fallback-pack", nil)

    self.h:installFallbackRuntime(host)
    local row = self.h:getFallbackMarkerRow()

    lu.assertNotNil(row)
    lu.assertTrue(row.visible())
end

function TestFallbackUi:testFallbackMarkerShowsWhenAnyFallbackRuntimeIsUncoordinated()
    local coordinatedHost = makeHost({ modpack = "fallback-pack" })
    local uncoordinatedHost = makeHost({ pluginGuid = "other-plugin", modpack = "other-pack" })
    self.h.coordinator.register("fallback-pack", { ModEnabled = true })
    self.h.coordinator.register("other-pack", nil)

    self.h:installFallbackRuntime(coordinatedHost)
    self.h:installFallbackRuntime(uncoordinatedHost)
    local row = self.h:getFallbackMarkerRow()

    lu.assertNotNil(row)
    lu.assertTrue(row.visible())
end

function TestFallbackUi:testMenuTogglesWindowAndRenderDrawsControls()
    local host = makeHost({ modpack = "fallback-pack" })
    self.h.coordinator.register("fallback-pack", nil)
    local imgui, calls = makeImgui({
        menuClicked = true,
        buttonClicks = {
            ["Resync State"] = true,
        },
    })
    self.h.rom.ImGui = imgui

    local runtime = self.h:installFallbackRuntime(host)
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(calls.beginMenu, 1)
    lu.assertEquals(calls.menuLabel, "Fallback UI Test")
    lu.assertEquals(calls.menuItem, "Fallback UI Test")
    lu.assertEquals(calls.setNextWindowSize, 1)
    lu.assertEquals(calls.title, "Fallback UI Test###FallbackUiTest")
    lu.assertEquals(calls.checkboxLabels, { "Enabled", "Debug Mode" })
    lu.assertEquals(host.calls.resync, 1)
    lu.assertEquals(host.calls.drawTab, 1)
    lu.assertEquals(host.calls.commitIfDirty, 1)
end

function TestFallbackUi:testFallbackWindowEndsImguiWindowWhenModuleDrawErrors()
    local host = makeHost({
        modpack = "fallback-pack",
        drawTabAndCommitThrows = true,
    })
    self.h.coordinator.register("fallback-pack", nil)
    local imgui, calls = makeImgui({ menuClicked = true })
    self.h.rom.ImGui = imgui

    local runtime = self.h:installFallbackRuntime(host)
    runtime.addMenuBar()
    local ok, err = pcall(runtime.renderWindow)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "draw tab boom")
    lu.assertEquals(calls.begin, 1)
    lu.assertEquals(calls.endWindow, 1)
end

function TestFallbackUi:testCloseFlushesRunDataAfterAffectingEnabledToggle()
    local setupCalls = 0
    self.h.game.setupRunData = function()
        setupCalls = setupCalls + 1
    end
    local host = makeHost({
        modpack = "fallback-pack",
        affectsRunData = true,
    })
    self.h.coordinator.register("fallback-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        open = false,
        checkboxValues = {
            Enabled = false,
        },
    })
    self.h.rom.ImGui = imgui

    local runtime = self.h:installFallbackRuntime(host)
    runtime.addMenuBar()
    runtime.renderWindow()
    runtime.renderWindow()

    lu.assertEquals(host.calls.setEnabled, { false })
    lu.assertEquals(setupCalls, 1)
end

function TestFallbackUi:testDebugToggleDoesNotMarkRunDataDirty()
    local setupCalls = 0
    self.h.game.setupRunData = function()
        setupCalls = setupCalls + 1
    end
    local host = makeHost({
        modpack = "fallback-pack",
        affectsRunData = true,
    })
    self.h.coordinator.register("fallback-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        open = false,
        checkboxValues = {
            ["Debug Mode"] = true,
        },
    })
    self.h.rom.ImGui = imgui

    local runtime = self.h:installFallbackRuntime(host)
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(host.calls.setDebugMode, { true })
    lu.assertEquals(setupCalls, 0)
end

function TestFallbackUi:testFallbackWindowSuppressesOverlaysUntilClose()
    local host = makeHost({ modpack = "fallback-pack" })
    self.h.coordinator.register("fallback-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        open = false,
    })
    self.h.rom.ImGui = imgui

    local runtime = self.h:installFallbackRuntime(host)
    runtime.addMenuBar()

    lu.assertEquals(self.h:countUiSuppressors(), 1)

    runtime.renderWindow()

    lu.assertEquals(self.h:countUiSuppressors(), 0)
end

function TestFallbackUi:testGuiClosedReleasesSuppressionWithoutClosingWindow()
    local host = makeHost({ modpack = "fallback-pack" })
    self.h.coordinator.register("fallback-pack", nil)
    local imgui = makeImgui({ menuClicked = true })
    self.h.rom.ImGui = imgui

    local runtime = self.h:installFallbackRuntime(host)
    runtime.addMenuBar()
    lu.assertEquals(self.h:countUiSuppressors(), 1)

    runtime.handleGuiClosed()
    lu.assertEquals(self.h:countUiSuppressors(), 0)

    runtime.renderWindow()

    lu.assertEquals(self.h:countUiSuppressors(), 1)
    lu.assertEquals(host.calls.drawTab, 1)
end
