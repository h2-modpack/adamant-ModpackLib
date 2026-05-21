local lu = require("luaunit")
local createWidgetHarness = require("tests/harness/create_widget_harness")

TestWidgets = {}

function TestWidgets:setUp()
    self.h = createWidgetHarness()
end

function TestWidgets:testPlainDropdownUsesNativePreview()
    local imgui, state = self.h.makeDropdownImgui()

    self.h.widgets.dropdown(imgui, self.h.createValueSession(2), "Mode", {
        label = "Mode",
        values = { 1, 2 },
        displayValues = {
            [1] = "One",
            [2] = "Two",
        },
        labelWidth = 80,
        controlWidth = 120,
    })

    lu.assertEquals(state.beginComboPreview, "Two")
    lu.assertEquals(state.customPreviewCalls, 0)
    lu.assertEquals(state.cursorPositions[1], 80)
end

function TestWidgets:testLabeledControlFallsBackToGapWhenLabelWidthIsTooSmall()
    local imgui, state = self.h.makeDropdownImgui()

    self.h.widgets.dropdown(imgui, self.h.createValueSession(2), "Mode", {
        label = "Long Label",
        values = { 1, 2 },
        labelWidth = 4,
        controlGap = 7,
    })

    lu.assertEquals(state.cursorPositions[1], 87)
end

function TestWidgets:testInputTextHonorsLabelWidth()
    local imgui, state = self.h.makeDropdownImgui()

    self.h.widgets.inputText(imgui, self.h.createValueSession("abc"), "Filter", {
        label = "Filter",
        labelWidth = 90,
        maxLen = 64,
    })

    lu.assertEquals(state.cursorPositions[1], 90)
    lu.assertEquals(state.inputText, { id = "##Filter", value = "abc", maxLen = 64 })
end

function TestWidgets:testColoredDropdownUsesCustomPreview()
    local imgui, state = self.h.makeDropdownImgui()

    self.h.widgets.dropdown(imgui, self.h.createValueSession(2), "Mode", {
        label = "Mode",
        values = { 1, 2 },
        displayValues = {
            [1] = "One",
            [2] = "Two",
        },
        valueColors = {
            [2] = { 1, 0, 0, 1 },
        },
        labelWidth = 80,
        controlWidth = 120,
    })

    lu.assertEquals(state.beginComboPreview, "")
    lu.assertEquals(state.customPreviewCalls, 1)
end

function TestWidgets:testStepperSupportsCalcTextSizeNumberReturn()
    local imgui = self.h.makeDropdownImgui()

    local ok = pcall(function()
        self.h.widgets.stepper(imgui, self.h.createValueSession(3), "Runs", {
            label = "Runs",
            min = 1,
            max = 10,
            valueWidth = 24,
        })
    end)

    lu.assertTrue(ok)
end

function TestWidgets:testStepperUsesStableButtonIdsAndWritesIncrement()
    local imgui, clickedButtons = self.h.makeStepperImgui("+##Runs_inc")
    local session = self.h.createValueSession(3)

    local changed = self.h.widgets.stepper(imgui, session, "Runs", {
        label = "Runs",
        min = 1,
        max = 10,
        valueWidth = 24,
    })

    lu.assertTrue(changed)
    lu.assertEquals(session.read("Runs"), 4)
    lu.assertEquals(clickedButtons[1], "-##Runs_dec")
    lu.assertEquals(clickedButtons[2], "+##Runs_inc")
end

function TestWidgets:testPackedDropdownResolvesChildrenFromSessionSchema()
    local session = self.h.createPackedSession()
    session.write("Second", true)
    local imgui, state = self.h.makeDropdownImgui()

    self.h.widgets.packedDropdown(imgui, session, "Packed", {
        label = "Packed",
        displayValues = {
            Second = "Second Choice",
        },
    })

    lu.assertEquals(state.beginComboPreview, "")
    lu.assertEquals(state.customPreviewText, "Second Choice")
end

function TestWidgets:testBoundPackedDropdownAcceptsTableRowStorageField()
    local definition = self.h.prepareDefinition({
        id = "PackedWidgetRowTest",
        name = "Packed Widget Row Test",
        storage = {
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    {
                        type = "packedInt",
                        alias = "Packed",
                        bits = {
                            { alias = "First", offset = 0, width = 1, type = "bool", default = false },
                            { alias = "Second", offset = 1, width = 1, type = "bool", default = false },
                        },
                    },
                },
            },
        },
    })
    local _, session = self.h.createModuleState({}, definition)
    local row = session.table("Rows"):rowHandle(1)
    row.write("Second", true)
    local imgui, state = self.h.makeDropdownImgui()

    self.h.widgets.bind(imgui, session).packedDropdown(row:field("Packed"), {
        label = "Packed",
        displayValues = {
            Second = "Second Choice",
        },
    })

    lu.assertEquals(state.customPreviewText, "Second Choice")
end

function TestWidgets:testBoundPackedChoiceAliasAcceptsTableRowStorageField()
    local definition = self.h.prepareDefinition({
        id = "PackedWidgetChoiceAliasFieldTest",
        name = "Packed Widget Choice Alias Field Test",
        storage = {
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    {
                        type = "packedInt",
                        alias = "Packed",
                        bits = {
                            { alias = "First", offset = 0, width = 1, type = "bool", default = false },
                            { alias = "Second", offset = 1, width = 1, type = "bool", default = false },
                        },
                    },
                },
            },
        },
    })
    local _, session = self.h.createModuleState({}, definition)
    local row = session.table("Rows"):rowHandle(1)
    row.write("Second", true)
    local imgui = self.h.makeDropdownImgui()

    local selected = self.h.widgets.bind(imgui, session).getPackedChoiceAlias(row:field("Packed"))

    lu.assertEquals(selected, "Second")
end

function TestWidgets:testBoundWidgetsRejectUnbrandedTableTargets()
    local session = self.h.createPackedSession()
    local imgui = self.h.makeDropdownImgui()
    local bound = self.h.widgets.bind(imgui, session)

    lu.assertErrorMsgContains("expected root alias string or StorageField", function()
        bound.dropdown({ alias = "Packed" }, {})
    end)
end

function TestWidgets:testPackedDropdownSupportsExplicitControlId()
    local session = self.h.createPackedSession()
    local imgui, state = self.h.makeDropdownImgui()

    self.h.widgets.packedDropdown(imgui, session, "Packed", {
        id = "Packed_Row_2",
        label = "Packed",
    })

    lu.assertEquals(state.beginComboId, "##Packed_Row_2")
end

function TestWidgets:testButtonRejectsRawActionKey()
    local imgui = self.h.makeDropdownImgui()
    imgui.Button = function(label)
        return true
    end

    lu.assertErrorMsgContains("widgets.invalid_action", function()
        self.h.widgets.button(imgui, "Start", {
            id = "start_recording",
            action = "recording",
            value = { kind = "start" },
        })
    end)
end

function TestWidgets:testButtonStagesDrawActionRef()
    local actionState = self.h.moduleState.createActionState()
    local action = self.h.moduleState.createDrawActions(actionState).get("recording")
    local clickedLabels = {}
    local imgui = self.h.makeDropdownImgui()
    imgui.Button = function(label)
        clickedLabels[#clickedLabels + 1] = label
        return true
    end

    local clicked = self.h.widgets.button(imgui, "Start", {
        id = "start_recording",
        action = action,
        value = { kind = "start" },
    })

    lu.assertTrue(clicked)
    lu.assertEquals(clickedLabels[1], "Start##start_recording")
    lu.assertEquals(action:read(), { kind = "start" })
end
