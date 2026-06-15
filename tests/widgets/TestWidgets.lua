local lu = require("luaunit")
local createWidgetHarness = require("tests/harness/create_widget_harness")

TestWidgets = {}

local function createWritableStagedState(values, schemas)
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

local function UseImgui(h, imgui)
    for key in pairs(h.rom.ImGui) do
        h.rom.ImGui[key] = nil
    end
    for key, value in pairs(imgui) do
        h.rom.ImGui[key] = value
    end
end

local function InDraw(_, callback)
    return callback()
end

local function DrawSurface(h, surface)
    return setmetatable({}, {
        __index = function(_, key)
            local value = surface[key]
            if type(value) ~= "function" then
                return value
            end
            return function(...)
                local args = { ... }
                return InDraw(h, function()
                    return value(table.unpack(args))
                end)
            end
        end,
    })
end

local function DrawWidgets(h, imgui)
    UseImgui(h, imgui)
    return DrawSurface(h, h.uiDraw.get().widgets)
end

local function DrawAction(h, actionBuffer, key)
    local actions = h.uiActions.create(actionBuffer)
    return InDraw(h, function()
        return actions.get(key)
    end)
end

function TestWidgets:testPlainDropdownUsesNativePreview()
    local imgui, state = self.h.makeDropdownImgui()
    local stagedState = self.h.createValueStagedState(2)

    DrawWidgets(self.h, imgui).dropdown(Field(self.h, stagedState, "Mode"), {
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

function TestWidgets:testDropdownBuildsIntegerValueRange()
    local imgui, state = self.h.makeDropdownImgui()
    local stagedState = self.h.createValueStagedState(0)
    local selectableLabels = {}
    imgui.BeginCombo = function(id, preview)
        state.beginComboId = id
        state.beginComboPreview = preview
        return true
    end
    imgui.Selectable = function(label)
        selectableLabels[#selectableLabels + 1] = label
        return false
    end
    imgui.EndCombo = function() end

    DrawWidgets(self.h, imgui).dropdown(Field(self.h, stagedState, "Delay"), {
        valueRange = {
            min = 0,
            max = 10,
            step = 5,
            suffix = "s",
        },
        displayValues = {
            [0] = "Off",
        },
    })

    lu.assertEquals(state.beginComboPreview, "Off")
    lu.assertEquals(selectableLabels, { "Off##1", "5s##2", "10s##3" })
end

function TestWidgets:testDropdownValueRangeSupportsPrependedValues()
    local imgui, state = self.h.makeDropdownImgui()
    local stagedState = self.h.createValueStagedState(1)
    local selectableLabels = {}
    imgui.BeginCombo = function(id, preview)
        state.beginComboId = id
        state.beginComboPreview = preview
        return true
    end
    imgui.Selectable = function(label)
        selectableLabels[#selectableLabels + 1] = label
        return false
    end
    imgui.EndCombo = function() end

    DrawWidgets(self.h, imgui).dropdown(Field(self.h, stagedState, "Recovery"), {
        valueRange = {
            min = 5,
            max = 10,
            step = 5,
            prepend = { 1 },
            suffix = "%",
        },
    })

    lu.assertEquals(state.beginComboPreview, "1%")
    lu.assertEquals(selectableLabels, { "1%##1", "5%##2", "10%##3" })
end

function TestWidgets:testDropdownExplicitValuesOverrideValueRange()
    local imgui, state = self.h.makeDropdownImgui()
    local stagedState = self.h.createValueStagedState(2)
    local selectableLabels = {}
    imgui.BeginCombo = function(id, preview)
        state.beginComboId = id
        state.beginComboPreview = preview
        return true
    end
    imgui.Selectable = function(label)
        selectableLabels[#selectableLabels + 1] = label
        return false
    end
    imgui.EndCombo = function() end

    DrawWidgets(self.h, imgui).dropdown(Field(self.h, stagedState, "Mode"), {
        values = { 2, 4 },
        valueRange = {
            min = 0,
            max = 10,
        },
    })

    lu.assertEquals(state.beginComboPreview, "2")
    lu.assertEquals(selectableLabels, { "2##1", "4##2" })
end

function TestWidgets:testDropdownCachesGeneratedValueRange()
    local suffixCount = 0
    local suffix = setmetatable({}, {
        __tostring = function()
            suffixCount = suffixCount + 1
            return "s"
        end,
    })
    local opts = {
        valueRange = {
            min = 0,
            max = 10,
            step = 5,
            suffix = suffix,
        },
    }
    local stagedState = self.h.createValueStagedState(5)

    DrawWidgets(self.h, self.h.makeDropdownImgui()).dropdown(Field(self.h, stagedState, "Delay"), opts)
    lu.assertEquals(suffixCount, 1)

    DrawWidgets(self.h, self.h.makeDropdownImgui()).dropdown(Field(self.h, stagedState, "Delay"), opts)
    lu.assertEquals(suffixCount, 1)
end

function TestWidgets:testLabeledControlFallsBackToGapWhenLabelWidthIsTooSmall()
    local imgui, state = self.h.makeDropdownImgui()
    local stagedState = self.h.createValueStagedState(2)

    DrawWidgets(self.h, imgui).dropdown(Field(self.h, stagedState, "Mode"), {
        label = "Long Label",
        values = { 1, 2 },
        labelWidth = 4,
        controlGap = 7,
    })

    lu.assertEquals(state.cursorPositions[1], 87)
end

function TestWidgets:testInputTextHonorsLabelWidth()
    local imgui, state = self.h.makeDropdownImgui()
    local stagedState = self.h.createValueStagedState("abc")

    DrawWidgets(self.h, imgui).inputText(Field(self.h, stagedState, "Filter"), {
        label = "Filter",
        labelWidth = 90,
        maxLen = 64,
    })

    lu.assertEquals(state.cursorPositions[1], 90)
    lu.assertEquals(state.inputText, { id = "##Filter", value = "abc", maxLen = 64 })
end

function TestWidgets:testInputTextSupportsExplicitControlId()
    local imgui, state = self.h.makeDropdownImgui()
    local stagedState = self.h.createValueStagedState("abc")

    DrawWidgets(self.h, imgui).inputText(Field(self.h, stagedState, "Filter"), {
        id = "Filter_2",
    })

    lu.assertEquals(state.inputText.id, "##Filter_2")
end

function TestWidgets:testColoredDropdownUsesCustomPreview()
    local imgui, state = self.h.makeDropdownImgui()
    local stagedState = self.h.createValueStagedState(2)

    DrawWidgets(self.h, imgui).dropdown(Field(self.h, stagedState, "Mode"), {
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

function TestWidgets:testTextColorUsesDefaultAlphaWithoutAllocatingNormalizedColor()
    local imgui, state = self.h.makeDropdownImgui()
    imgui.Text = function(text)
        state.plainText = text
    end
    imgui.TextColored = function(r, g, b, a, text)
        state.coloredText = { r = r, g = g, b = b, a = a, text = text }
    end

    DrawWidgets(self.h, imgui).text("Warning", {
        color = { 0.8, 0.2, 0.1 },
    })

    lu.assertNil(state.plainText)
    lu.assertEquals(state.coloredText, { r = 0.8, g = 0.2, b = 0.1, a = 1, text = "Warning" })
end

function TestWidgets:testCheckboxColorUsesDefaultAlphaWithoutDrawClosure()
    local imgui, state = self.h.makeDropdownImgui()
    imgui.ImGuiCol = { Text = 7 }
    imgui.PushStyleColor = function(...)
        state.pushedColor = { ... }
    end
    imgui.PopStyleColor = function()
        state.popCount = (state.popCount or 0) + 1
    end
    imgui.Checkbox = function(label, current)
        state.checkboxLabel = label
        return current, false
    end
    local stagedState = self.h.createValueStagedState(true)

    DrawWidgets(self.h, imgui).checkbox(Field(self.h, stagedState, "Enabled"), {
        color = { 0.1, 0.2, 0.3 },
    })

    lu.assertEquals(state.checkboxLabel, "Enabled##Enabled")
    lu.assertEquals(state.pushedColor, { 7, 0.1, 0.2, 0.3, 1 })
    lu.assertEquals(state.popCount, 1)
end

function TestWidgets:testStepperSupportsCalcTextSizeNumberReturn()
    local imgui = self.h.makeDropdownImgui()
    local stagedState = self.h.createValueStagedState(3)

    local ok = pcall(function()
        DrawWidgets(self.h, imgui).stepper(Field(self.h, stagedState, "Runs"), {
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
    local stagedState = self.h.createValueStagedState(3)

    local changed = DrawWidgets(self.h, imgui).stepper(Field(self.h, stagedState, "Runs"), {
        label = "Runs",
        min = 1,
        max = 10,
        valueWidth = 24,
    })

    lu.assertTrue(changed)
    lu.assertEquals(stagedState.read("Runs"), 4)
    lu.assertEquals(clickedButtons[1], "-##Runs_dec")
    lu.assertEquals(clickedButtons[2], "+##Runs_inc")
end

function TestWidgets:testPackedDropdownResolvesChildrenFromStagedStateSchema()
    local stagedState = self.h.createPackedStagedState()
    stagedState.write("Second", true)
    local imgui, state = self.h.makeDropdownImgui()

    DrawWidgets(self.h, imgui).packedDropdown(stagedState.get("Packed"), {
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
                        width = 2,
                        bits = {
                            { alias = "First", offset = 0, width = 1, type = "bool", default = false },
                            { alias = "Second", offset = 1, width = 1, type = "bool", default = false },
                        },
                    },
                },
            },
        },
    })
    local _, stagedState = self.h.createModuleState({}, definition)
    local rows = stagedState.table("Rows")
    rows:write(1, "Second", true)
    local imgui, state = self.h.makeDropdownImgui()

    DrawWidgets(self.h, imgui).packedDropdown(rows:get(1, "Packed"), {
        label = "Packed",
        displayValues = {
            Second = "Second Choice",
        },
    })

    lu.assertEquals(state.beginComboId, "##Rows:1:Packed")
    lu.assertEquals(state.customPreviewText, "Second Choice")
end

function TestWidgets:testDrawWidgetsAcceptStagedStateGetStorageField()
    local stagedState = self.h.createPackedStagedState()
    stagedState.write("Second", true)
    local imgui, state = self.h.makeDropdownImgui()

    DrawWidgets(self.h, imgui).packedDropdown(stagedState.get("Packed"), {
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
                        width = 2,
                        bits = {
                            { alias = "First", offset = 0, width = 1, type = "bool", default = false },
                            { alias = "Second", offset = 1, width = 1, type = "bool", default = false },
                        },
                    },
                },
            },
        },
    })
    local _, stagedState = self.h.createModuleState({}, definition)
    local rows = stagedState.table("Rows")
    rows:write(1, "Second", true)
    local imgui = self.h.makeDropdownImgui()

    local selected = DrawWidgets(self.h, imgui).getPackedChoiceAlias(rows:get(1, "Packed"))

    lu.assertEquals(selected, "Second")
end

function TestWidgets:testDrawWidgetsRejectUnbrandedTableTargets()
    local imgui = self.h.makeDropdownImgui()
    local drawWidgets = DrawWidgets(self.h, imgui)

    lu.assertErrorMsgContains("expected StorageField", function()
        drawWidgets.dropdown({ alias = "Packed" }, {})
    end)
end

function TestWidgets:testPackedDropdownSupportsExplicitControlId()
    local stagedState = self.h.createPackedStagedState()
    local imgui, state = self.h.makeDropdownImgui()

    DrawWidgets(self.h, imgui).packedDropdown(stagedState.get("Packed"), {
        id = "Packed_Row_2",
        label = "Packed",
    })

    lu.assertEquals(state.beginComboId, "##Packed_Row_2")
end

function TestWidgets:testButtonRejectsRawActionKey()
    local imgui = self.h.makeDropdownImgui()
    imgui.Button = function()
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
    local actionBuffer = self.h.moduleState.createActionBuffer()
    local action = DrawAction(self.h, actionBuffer, "recording")
    local clickedLabels = {}
    local imgui = self.h.makeDropdownImgui()
    imgui.Button = function(label)
        clickedLabels[#clickedLabels + 1] = label
        return true
    end

    local clicked = DrawWidgets(self.h, imgui).button("Start", {
        id = "start_recording",
        action = action,
        value = { kind = "start" },
    })

    lu.assertTrue(clicked)
    lu.assertEquals(clickedLabels[1], "Start##start_recording")
    lu.assertEquals(actionBuffer.read("recording"), { kind = "start" })
end

function TestWidgets:testCheckboxStagesDrawActionRef()
    local actionBuffer = self.h.moduleState.createActionBuffer()
    local action = DrawAction(self.h, actionBuffer, "enabled")
    local stagedState = self.h.createValueStagedState(false)
    local imgui = self.h.makeDropdownImgui()
    imgui.Checkbox = function(_, current)
        return not current, true
    end

    local changed = DrawWidgets(self.h, imgui).checkbox(Field(self.h, stagedState, "Enabled"), {
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(stagedState.read("Enabled"), true)
    lu.assertEquals(actionBuffer.read("enabled"), true)
end

function TestWidgets:testDropdownStagesDrawActionRef()
    local actionBuffer = self.h.moduleState.createActionBuffer()
    local action = DrawAction(self.h, actionBuffer, "mode")
    local stagedState = self.h.createValueStagedState(1)
    local imgui = self.h.makeDropdownImgui()
    imgui.BeginCombo = function()
        return true
    end
    imgui.Selectable = function(label)
        return label == "Two##2"
    end
    imgui.EndCombo = function() end

    local changed = DrawWidgets(self.h, imgui).dropdown(Field(self.h, stagedState, "Mode"), {
        values = { 1, 2 },
        displayValues = {
            [1] = "One",
            [2] = "Two",
        },
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(stagedState.read("Mode"), 2)
    lu.assertEquals(actionBuffer.read("mode"), 2)
end

function TestWidgets:testDropdownSkipsHiddenValues()
    local stagedState = self.h.createValueStagedState(2)
    local imgui, state = self.h.makeDropdownImgui()
    local selectableLabels = {}
    imgui.BeginCombo = function(id, preview)
        state.beginComboId = id
        state.beginComboPreview = preview
        return true
    end
    imgui.Selectable = function(label)
        selectableLabels[#selectableLabels + 1] = label
        return label == "Three##3"
    end
    imgui.EndCombo = function() end

    local changed = DrawWidgets(self.h, imgui).dropdown(Field(self.h, stagedState, "Mode"), {
        values = { 1, 2, 3 },
        displayValues = {
            [1] = "One",
            [2] = "Two",
            [3] = "Three",
        },
        visibleValues = {
            [2] = false,
        },
    })

    lu.assertTrue(changed)
    lu.assertEquals(state.beginComboPreview, "One")
    lu.assertEquals(selectableLabels, { "One##1", "Three##3" })
    lu.assertEquals(stagedState.read("Mode"), 3)
end

function TestWidgets:testStepperStagesDrawActionRef()
    local actionBuffer = self.h.moduleState.createActionBuffer()
    local action = DrawAction(self.h, actionBuffer, "runs")
    local imgui = self.h.makeStepperImgui("+##Runs_inc")
    local stagedState = self.h.createValueStagedState(3)

    local changed = DrawWidgets(self.h, imgui).stepper(Field(self.h, stagedState, "Runs"), {
        min = 1,
        max = 10,
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(stagedState.read("Runs"), 4)
    lu.assertEquals(actionBuffer.read("runs"), 4)
end

function TestWidgets:testRadioStagesDrawActionRef()
    local actionBuffer = self.h.moduleState.createActionBuffer()
    local action = DrawAction(self.h, actionBuffer, "mode")
    local imgui = self.h.makeDropdownImgui()
    imgui.RadioButton = function(label)
        return label == "Two##Mode_2"
    end
    local stagedState = self.h.createValueStagedState(1)

    local changed = DrawWidgets(self.h, imgui).radio(Field(self.h, stagedState, "Mode"), {
        values = { 1, 2 },
        displayValues = {
            [1] = "One",
            [2] = "Two",
        },
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(stagedState.read("Mode"), 2)
    lu.assertEquals(actionBuffer.read("mode"), 2)
end

function TestWidgets:testRadioSkipsHiddenValues()
    local imgui = self.h.makeDropdownImgui()
    local radioLabels = {}
    imgui.RadioButton = function(label)
        radioLabels[#radioLabels + 1] = label
        return label == "Three##Mode_3"
    end
    local stagedState = self.h.createValueStagedState(2)

    local changed = DrawWidgets(self.h, imgui).radio(Field(self.h, stagedState, "Mode"), {
        values = { 1, 2, 3 },
        displayValues = {
            [1] = "One",
            [2] = "Two",
            [3] = "Three",
        },
        visibleValues = {
            [2] = false,
        },
    })

    lu.assertTrue(changed)
    lu.assertEquals(radioLabels, { "One##Mode_1", "Three##Mode_3" })
    lu.assertEquals(stagedState.read("Mode"), 3)
end

function TestWidgets:testPackedRadioStagesSelectedChildAction()
    local actionBuffer = self.h.moduleState.createActionBuffer()
    local action = DrawAction(self.h, actionBuffer, "packed")
    local imgui = self.h.makeDropdownImgui()
    imgui.RadioButton = function(label)
        return label == "First##Packed_2"
    end
    local stagedState = self.h.createPackedStagedState()

    local changed = DrawWidgets(self.h, imgui).packedRadio(stagedState.get("Packed"), {
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(stagedState.read("First"), true)
    lu.assertEquals(stagedState.read("Second"), false)
    lu.assertEquals(actionBuffer.read("packed"), "First")
end

function TestWidgets:testSteppedRangeStagesDrawActionRef()
    local actionBuffer = self.h.moduleState.createActionBuffer()
    local action = DrawAction(self.h, actionBuffer, "range")
    local imgui = self.h.makeStepperImgui("+##Max_max_inc")
    local stagedState = createWritableStagedState({
        Min = 2,
        Max = 4,
    }, {
        Min = { alias = "Min", type = "int" },
        Max = { alias = "Max", type = "int" },
    })

    local changed = DrawWidgets(self.h, imgui).steppedRange(
        Field(self.h, stagedState, "Min"),
        Field(self.h, stagedState, "Max"),
        {
        min = 1,
        max = 10,
        action = action,
    })

    lu.assertTrue(changed)
    lu.assertEquals(stagedState.read("Min"), 2)
    lu.assertEquals(stagedState.read("Max"), 5)
    lu.assertEquals(actionBuffer.read("range"), { min = 2, max = 5 })
end
