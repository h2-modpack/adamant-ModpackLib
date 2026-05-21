local lu = require("luaunit")
local createWidgetHarness = require("tests/harness/create_widget_harness")

TestWidgets = {}

local function createWritableSession(values, schemas)
    return {
        view = values,
        read = function(alias)
            return values[alias]
        end,
        write = function(alias, value)
            values[alias] = value
        end,
        getAliasSchema = function(alias)
            return schemas and schemas[alias] or { alias = alias, type = "int" }
        end,
    }
end

function TestWidgets:setUp()
    self.h = createWidgetHarness()
end

local function Field(h, owner, alias)
    return h.createField(owner, alias)
end

function TestWidgets:testPlainDropdownUsesNativePreview()
    local imgui, state = self.h.makeDropdownImgui()
    local session = self.h.createValueSession(2)

    self.h.widgets.bind(imgui).dropdown(Field(self.h, session, "Mode"), {
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
    local session = self.h.createValueSession(2)

    self.h.widgets.bind(imgui).dropdown(Field(self.h, session, "Mode"), {
        label = "Long Label",
        values = { 1, 2 },
        labelWidth = 4,
        controlGap = 7,
    })

    lu.assertEquals(state.cursorPositions[1], 87)
end

function TestWidgets:testInputTextHonorsLabelWidth()
    local imgui, state = self.h.makeDropdownImgui()
    local session = self.h.createValueSession("abc")

    self.h.widgets.bind(imgui).inputText(Field(self.h, session, "Filter"), {
        label = "Filter",
        labelWidth = 90,
        maxLen = 64,
    })

    lu.assertEquals(state.cursorPositions[1], 90)
    lu.assertEquals(state.inputText, { id = "##Filter", value = "abc", maxLen = 64 })
end

function TestWidgets:testColoredDropdownUsesCustomPreview()
    local imgui, state = self.h.makeDropdownImgui()
    local session = self.h.createValueSession(2)

    self.h.widgets.bind(imgui).dropdown(Field(self.h, session, "Mode"), {
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
    local session = self.h.createValueSession(3)

    local ok = pcall(function()
        self.h.widgets.bind(imgui).stepper(Field(self.h, session, "Runs"), {
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

    local changed = self.h.widgets.bind(imgui).stepper(Field(self.h, session, "Runs"), {
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

    self.h.widgets.bind(imgui).packedDropdown(session.get("Packed"), {
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
    local rows = session.table("Rows")
    rows:write(1, "Second", true)
    local imgui, state = self.h.makeDropdownImgui()

    self.h.widgets.bind(imgui).packedDropdown(rows:get(1, "Packed"), {
        label = "Packed",
        displayValues = {
            Second = "Second Choice",
        },
    })

    lu.assertEquals(state.beginComboId, "##Rows:1:Packed")
    lu.assertEquals(state.customPreviewText, "Second Choice")
end

function TestWidgets:testBoundWidgetsAcceptSessionGetStorageField()
    local session = self.h.createPackedSession()
    session.write("Second", true)
    local imgui, state = self.h.makeDropdownImgui()

    self.h.widgets.bind(imgui).packedDropdown(session.get("Packed"), {
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
    local rows = session.table("Rows")
    rows:write(1, "Second", true)
    local imgui = self.h.makeDropdownImgui()

    local selected = self.h.widgets.bind(imgui).getPackedChoiceAlias(rows:get(1, "Packed"))

    lu.assertEquals(selected, "Second")
end

function TestWidgets:testBoundWidgetsRejectUnbrandedTableTargets()
    local imgui = self.h.makeDropdownImgui()
    local bound = self.h.widgets.bind(imgui)

    lu.assertErrorMsgContains("expected StorageField", function()
        bound.dropdown({ alias = "Packed" }, {})
    end)
end

function TestWidgets:testPackedDropdownSupportsExplicitControlId()
    local session = self.h.createPackedSession()
    local imgui, state = self.h.makeDropdownImgui()

    self.h.widgets.bind(imgui).packedDropdown(session.get("Packed"), {
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

function TestWidgets:testCheckboxStagesDrawActionRef()
    local actionState = self.h.moduleState.createActionState()
    local action = self.h.moduleState.createDrawActions(actionState).get("enabled")
    local session = self.h.createValueSession(false)
    local imgui = self.h.makeDropdownImgui()
    imgui.Checkbox = function(_, current)
        return not current, true
    end

    local changed = self.h.widgets.bind(imgui).checkbox(Field(self.h, session, "Enabled"), {
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(session.read("Enabled"), true)
    lu.assertEquals(action:read(), true)
end

function TestWidgets:testDropdownStagesDrawActionRef()
    local actionState = self.h.moduleState.createActionState()
    local action = self.h.moduleState.createDrawActions(actionState).get("mode")
    local session = self.h.createValueSession(1)
    local imgui = self.h.makeDropdownImgui()
    imgui.BeginCombo = function()
        return true
    end
    imgui.Selectable = function(label)
        return label == "Two##2"
    end
    imgui.EndCombo = function() end

    local changed = self.h.widgets.bind(imgui).dropdown(Field(self.h, session, "Mode"), {
        values = { 1, 2 },
        displayValues = {
            [1] = "One",
            [2] = "Two",
        },
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(session.read("Mode"), 2)
    lu.assertEquals(action:read(), 2)
end

function TestWidgets:testStepperStagesDrawActionRef()
    local actionState = self.h.moduleState.createActionState()
    local action = self.h.moduleState.createDrawActions(actionState).get("runs")
    local imgui = self.h.makeStepperImgui("+##Runs_inc")
    local session = self.h.createValueSession(3)

    local changed = self.h.widgets.bind(imgui).stepper(Field(self.h, session, "Runs"), {
        min = 1,
        max = 10,
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(session.read("Runs"), 4)
    lu.assertEquals(action:read(), 4)
end

function TestWidgets:testRadioStagesDrawActionRef()
    local actionState = self.h.moduleState.createActionState()
    local action = self.h.moduleState.createDrawActions(actionState).get("mode")
    local imgui = self.h.makeDropdownImgui()
    imgui.RadioButton = function(label)
        return label == "Two##Mode_2"
    end
    local session = self.h.createValueSession(1)

    local changed = self.h.widgets.bind(imgui).radio(Field(self.h, session, "Mode"), {
        values = { 1, 2 },
        displayValues = {
            [1] = "One",
            [2] = "Two",
        },
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(session.read("Mode"), 2)
    lu.assertEquals(action:read(), 2)
end

function TestWidgets:testPackedRadioStagesSelectedChildAction()
    local actionState = self.h.moduleState.createActionState()
    local action = self.h.moduleState.createDrawActions(actionState).get("packed")
    local imgui = self.h.makeDropdownImgui()
    imgui.RadioButton = function(label)
        return label == "First##Packed_2"
    end
    local session = self.h.createPackedSession()

    local changed = self.h.widgets.bind(imgui).packedRadio(session.get("Packed"), {
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(session.read("First"), true)
    lu.assertEquals(session.read("Second"), false)
    lu.assertEquals(action:read(), "First")
end

function TestWidgets:testSteppedRangeStagesDrawActionRef()
    local actionState = self.h.moduleState.createActionState()
    local action = self.h.moduleState.createDrawActions(actionState).get("range")
    local imgui = self.h.makeStepperImgui("+##Max_max_inc")
    local session = createWritableSession({
        Min = 2,
        Max = 4,
    }, {
        Min = { alias = "Min", type = "int" },
        Max = { alias = "Max", type = "int" },
    })

    local changed = self.h.widgets.bind(imgui).steppedRange(
        Field(self.h, session, "Min"),
        Field(self.h, session, "Max"),
        {
        min = 1,
        max = 10,
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(session.read("Min"), 2)
    lu.assertEquals(session.read("Max"), 5)
    lu.assertEquals(action:read(), { min = 2, max = 5 })
end
