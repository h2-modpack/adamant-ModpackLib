local lu = require("luaunit")
local createWidgetHarness = require("tests/harness/create_widget_harness")

TestWidgets_Nav = {}

function TestWidgets_Nav:setUp()
    self.h = createWidgetHarness()
end

local function InDraw(h, callback)
    return h.phaseGate.runDraw(callback)
end

function TestWidgets_Nav:testVerticalTabsReturnsSelectedKeyAndDrawsGroupsAndColors()
    local calls = {
        beginChild = 0,
        endChild = 0,
        sameLine = 0,
        separators = 0,
        groups = {},
        selectedLabels = {},
        pushColors = 0,
        popColors = 0,
    }
    local imgui = {
        ImGuiCol = { Text = 5 },
        BeginChild = function(id, width, height, border)
            calls.beginChild = calls.beginChild + 1
            calls.child = { id = id, width = width, height = height, border = border }
        end,
        EndChild = function()
            calls.endChild = calls.endChild + 1
        end,
        SameLine = function()
            calls.sameLine = calls.sameLine + 1
        end,
        Separator = function()
            calls.separators = calls.separators + 1
        end,
        TextDisabled = function(label)
            calls.groups[#calls.groups + 1] = label
        end,
        PushStyleColor = function(...)
            calls.pushColors = calls.pushColors + 1
            calls.colorArgs = { ... }
        end,
        PopStyleColor = function()
            calls.popColors = calls.popColors + 1
        end,
        Selectable = function(label, selected)
            calls.selectedLabels[#calls.selectedLabels + 1] = { label = label, selected = selected }
            return label == "Second##two"
        end,
    }

    local selected = self.h.nav.verticalTabs(imgui, {
        id = "modules",
        navWidth = 200,
        height = 300,
        activeKey = "one",
        tabs = {
            { key = "one", label = "First", group = "Group A" },
            { key = "two", label = "Second", group = "Group A", color = { 1, 0, 0, 1 } },
            { key = "three", label = "Third", group = "Group B" },
        },
    })

    lu.assertEquals(selected, "two")
    lu.assertEquals(calls.child, { id = "modules##nav", width = 200, height = 300, border = true })
    lu.assertEquals(calls.beginChild, 1)
    lu.assertEquals(calls.endChild, 1)
    lu.assertEquals(calls.sameLine, 1)
    lu.assertEquals(calls.groups, { "Group A", "Group B" })
    lu.assertEquals(calls.separators, 3)
    lu.assertEquals(calls.selectedLabels[1], { label = "First##one", selected = true })
    lu.assertEquals(calls.pushColors, 1)
    lu.assertEquals(calls.popColors, 1)
    lu.assertEquals(calls.colorArgs, { 5, 1, 0, 0, 1 })
end

function TestWidgets_Nav:testDrawNavUsesCurrentImguiForVerticalTabs()
    local calls = {
        labels = {},
    }
    local imgui = {
        BeginChild = function(id)
            calls.childId = id
        end,
        EndChild = function()
            calls.ended = true
        end,
        SameLine = function()
            calls.sameLine = true
        end,
        Separator = function()
        end,
        TextDisabled = function()
        end,
        Selectable = function(label)
            calls.labels[#calls.labels + 1] = label
            return label == "Second##two"
        end,
    }
    for key in pairs(self.h.rom.ImGui) do
        self.h.rom.ImGui[key] = nil
    end
    for key, value in pairs(imgui) do
        self.h.rom.ImGui[key] = value
    end
    local drawNav = self.h.uiDraw.get().nav

    local selected = InDraw(self.h, function()
        return drawNav.verticalTabs({
            id = "draw",
            activeKey = "one",
            tabs = {
                { key = "one", label = "First" },
                { key = "two", label = "Second" },
            },
        })
    end)

    lu.assertEquals(selected, "two")
    lu.assertEquals(calls.childId, "draw##nav")
    lu.assertEquals(calls.labels, { "First##one", "Second##two" })
    lu.assertTrue(calls.ended)
    lu.assertTrue(calls.sameLine)
end

function TestWidgets_Nav:testDrawNavRejectsUseOutsideDrawPhase()
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        self.h.uiDraw.get().nav.verticalTabs({})
    end)
end
