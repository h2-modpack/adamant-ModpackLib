local lu = require("luaunit")
local createOverlayHarness = require("tests/harness/create_overlay_harness")

TestOverlays = {}

function TestOverlays:setUp()
    self.h = createOverlayHarness()
end

function TestOverlays:dispatch(owner)
    return self.h.overlays.dispatchCommit(owner, {})
end

function TestOverlays:activateModuleWithOverlays(pluginGuid, declareOverlays, opts)
    local host, authorModule, store, stagedState = self.h.createModuleWithOverlays(pluginGuid, declareOverlays, opts)
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))
    return host, authorModule, store, stagedState
end

function TestOverlays:testRetainedLineUsesHudComponentAndVisibilityHooks()
    local modified = {}
    local alphas = {}
    local wrappedStartRoomPresentation = nil
    local text = "Ready"
    local visible = true

    self.h.modutil.Path.Wrap = function(path, handler)
        if path == "StartRoomPresentation" then
            wrappedStartRoomPresentation = handler
        end
    end
    self.h.game.modifyTextBox = function(args)
        modified[#modified + 1] = args
    end
    self.h.game.setAlpha = function(args)
        alphas[#alphas + 1] = args
    end

    self.h.createSystem("test.overlay.line").overlays.define(function(overlays)
        overlays.createLine("message", {
            componentName = "TestOverlay",
            region = "middleRightStack",
            visible = function()
                return visible
            end,
            minWidth = 80,
            textArgs = {
                Color = { 0.5, 0.5, 0.5, 1 },
            },
        })
        overlays.onCommit(function(overlay)
            overlay.setLine("message", text)
            overlay.refresh("message")
        end)
    end)

    local componentData = self.h.game.screenData.HUD.ComponentData.AdamantOverlay_TestOverlay_text
    lu.assertNotNil(wrappedStartRoomPresentation)
    lu.assertEquals(componentData.TextArgs.Text, "")
    lu.assertEquals(componentData.TextArgs.Color, { 0.5, 0.5, 0.5, 1 })
    lu.assertEquals(modified[#modified].Text, "Ready")

    text = "Updated"
    self:dispatch("test.overlay.line")

    lu.assertEquals(modified[#modified].Text, "Updated")

    visible = false
    self:dispatch("test.overlay.line")

    lu.assertEquals(alphas[#alphas].Fraction, 0.0)

    visible = true
    wrappedStartRoomPresentation(function() end, {}, {})

    lu.assertEquals(alphas[#alphas].Fraction, 1.0)
end

function TestOverlays:testRetainedLinesUseStableMiddleRightOrderingAndBands()
    local system = self.h.createSystem("test.overlay.order")
    system.overlays.define(function(overlays)
        overlays.createLine("module", {
            componentName = "ModuleOverlay",
            region = "middleRightStack",
            minWidth = 80,
        })
        overlays.createLine("system", {
            componentName = "SystemOverlay",
            region = "middleRightStack",
            order = system.overlays.order.system + 1,
            minWidth = 80,
        })
        overlays.createLine("debug", {
            componentName = "DebugOverlay",
            region = "middleRightStack",
            order = system.overlays.order.debug,
            minWidth = 80,
        })
        overlays.onCommit(function(overlay)
            overlay.setLine("module", "Module")
            overlay.setLine("system", "System")
            overlay.setLine("debug", "Debug")
            overlay.refreshRegion("middleRightStack")
        end)
    end)

    lu.assertEquals(self.h.game.screenData.HUD.ComponentData.AdamantOverlay_SystemOverlay_text.Y, 200)
    lu.assertEquals(self.h.game.screenData.HUD.ComponentData.AdamantOverlay_ModuleOverlay_text.Y, 240)
    lu.assertEquals(self.h.game.screenData.HUD.ComponentData.AdamantOverlay_DebugOverlay_text.Y, 280)
end

function TestOverlays:testRetainedLineSupportsCenterLowerStackRegion()
    self.h.game.screenCenterX = 800
    self.h.game.screenHeight = 900

    local system = self.h.createSystem("test.overlay.center.lower")
    system.overlays.define(function(overlays)
        overlays.createLine("message", {
            componentName = "CenterOverlay",
            region = "centerLowerStack",
            minWidth = 180,
            justify = "Center",
            textArgs = {
                Font = "P22UndergroundSCMedium",
            },
        })
        overlays.createLine("columns", {
            componentName = "CenterColumns",
            region = "centerLowerStack",
            order = system.overlays.order.module + 1,
            columnGap = 10,
            columns = {
                {
                    key = "label",
                    minWidth = 100,
                    justify = "Left",
                },
                {
                    key = "value",
                    minWidth = 50,
                    justify = "Right",
                },
            },
        })
        overlays.onCommit(function(overlay)
            overlay.setLine("message", "Penalty")
            overlay.setLine("columns", {
                label = "Penalty",
                value = "30s",
            })
            overlay.refreshRegion("centerLowerStack")
        end)
    end)
    self:dispatch("test.overlay.center.lower")

    local message = self.h.game.screenData.HUD.ComponentData.AdamantOverlay_CenterOverlay_text
    local label = self.h.game.screenData.HUD.ComponentData.AdamantOverlay_CenterColumns_label
    local value = self.h.game.screenData.HUD.ComponentData.AdamantOverlay_CenterColumns_value
    lu.assertEquals(message.X, 800)
    lu.assertNil(message.RightOffset)
    lu.assertEquals(message.Y, 540)
    lu.assertEquals(message.TextArgs.Justification, "Center")
    lu.assertEquals(message.TextArgs.VerticalJustification, "Center")
    lu.assertEquals(message.TextArgs.FontSize, 22)
    lu.assertEquals(label.X, 720)
    lu.assertEquals(value.X, 880)
    lu.assertEquals(label.Y, 576)
    lu.assertEquals(value.Y, 576)
    lu.assertEquals(label.TextArgs.Justification, "Left")
    lu.assertEquals(value.TextArgs.Justification, "Right")
end

function TestOverlays:testRetainedTableUsesStableColumnSpacing()
    local host = self:activateModuleWithOverlays("test.overlay.table", function(overlays)
        overlays.createTable("timer", {
            componentName = "TimerTable",
            region = "middleRightStack",
            maxRows = 1,
            columnGap = 6,
            columns = {
                {
                    key = "label",
                    minWidth = 42,
                    justify = "Right",
                    textArgs = {
                        Font = "P22UndergroundSCMedium",
                    },
                },
                {
                    key = "time",
                    minWidth = 96,
                    justify = "Right",
                    textArgs = {
                        Font = "MonospaceTypewriterBold",
                    },
                },
            },
        })
        overlays.onCommit(function(_, _, overlay)
            overlay.setTable("timer", {
                { key = "row", label = "IGT:", time = "00:00.00" },
            })
            overlay.refresh("timer")
        end)
    end)
    self:dispatch(host)

    local label = self.h.game.screenData.HUD.ComponentData.AdamantOverlay_TimerTable_1_label
    local time = self.h.game.screenData.HUD.ComponentData.AdamantOverlay_TimerTable_1_time
    lu.assertEquals(label.RightOffset, 112)
    lu.assertEquals(time.RightOffset, 10)
    lu.assertEquals(label.Y, 200)
    lu.assertEquals(time.Y, 200)
    lu.assertEquals(label.TextArgs.Font, "P22UndergroundSCMedium")
    lu.assertEquals(time.TextArgs.Font, "MonospaceTypewriterBold")
end

function TestOverlays:testUiSuppressionTokenGloballyHidesAndRestoresRetainedOverlays()
    local alphas = {}
    self.h.game.setAlpha = function(args)
        alphas[#alphas + 1] = args
    end

    self.h.createSystem("test.overlay.suppression").overlays.define(function(overlays)
        overlays.createLine("line", {
            componentName = "SuppressedOverlay",
            region = "middleRightStack",
            minWidth = 80,
        })
        overlays.onCommit(function(overlay)
            overlay.setLine("line", "Visible")
            overlay.refresh("line")
        end)
    end)

    lu.assertFalse(self.h.overlays.isUiSuppressed())

    local firstToken = self.h.overlays.suppressForUi()
    lu.assertTrue(self.h.overlays.isUiSuppressed())
    lu.assertEquals(alphas[#alphas].Fraction, 0.0)

    local secondToken = self.h.overlays.suppressForUi()
    firstToken.release()
    lu.assertTrue(self.h.overlays.isUiSuppressed())
    lu.assertEquals(alphas[#alphas].Fraction, 0.0)

    secondToken.release()
    lu.assertFalse(self.h.overlays.isUiSuppressed())
    lu.assertEquals(alphas[#alphas].Fraction, 1.0)

    secondToken.release()
    lu.assertFalse(self.h.overlays.isUiSuppressed())
end
