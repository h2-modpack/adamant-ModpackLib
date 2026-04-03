local lu = require('luaunit')

-- =============================================================================
-- CHECKBOX
-- =============================================================================

TestCheckbox = {}

function TestCheckbox:testToHashTrue()
    local field = { type = "checkbox", configKey = "X" }
    lu.assertEquals(lib.FieldTypes.checkbox.toHash(field, true), "1")
end

function TestCheckbox:testToHashFalse()
    local field = { type = "checkbox", configKey = "X" }
    lu.assertEquals(lib.FieldTypes.checkbox.toHash(field, false), "0")
end

function TestCheckbox:testFromHashOne()
    local field = { type = "checkbox", configKey = "X" }
    lu.assertEquals(lib.FieldTypes.checkbox.fromHash(field, "1"), true)
end

function TestCheckbox:testFromHashZero()
    local field = { type = "checkbox", configKey = "X" }
    lu.assertEquals(lib.FieldTypes.checkbox.fromHash(field, "0"), false)
end

function TestCheckbox:testToStagingTrue()
    lu.assertEquals(lib.FieldTypes.checkbox.toStaging(true), true)
end

function TestCheckbox:testToStagingFalse()
    lu.assertEquals(lib.FieldTypes.checkbox.toStaging(false), false)
end

function TestCheckbox:testToStagingNil()
    lu.assertEquals(lib.FieldTypes.checkbox.toStaging(nil), false)
end

-- =============================================================================
-- DROPDOWN
-- =============================================================================

TestString = {}

local stringField = {
    type = "string",
    configKey = "Label",
    default = "Default",
    maxLen = 64,
}

function TestString:testToHash()
    lu.assertEquals(lib.FieldTypes.string.toHash(stringField, "BridalGlow"), "BridalGlow")
end

function TestString:testFromHash()
    lu.assertEquals(lib.FieldTypes.string.fromHash(stringField, "BridalGlow"), "BridalGlow")
end

function TestString:testFromHashNilFallsBackToDefault()
    lu.assertEquals(lib.FieldTypes.string.fromHash(stringField, nil), "Default")
end

function TestString:testToStaging()
    lu.assertEquals(lib.FieldTypes.string.toStaging("Apollo", stringField), "Apollo")
end

function TestString:testToStagingNilFallsBackToDefault()
    lu.assertEquals(lib.FieldTypes.string.toStaging(nil, stringField), "Default")
end

function TestString:testValidateWarnsOnBadDefault()
    local field = { type = "string", configKey = "X", default = false }
    CaptureWarnings()
    lib.FieldTypes.string.validate(field, "test")
    local warned = #Warnings > 0
    RestoreWarnings()
    lu.assertTrue(warned)
end

function TestString:testValidateWarnsOnBadMaxLen()
    local field = { type = "string", configKey = "X", default = "", maxLen = 0 }
    CaptureWarnings()
    lib.FieldTypes.string.validate(field, "test")
    local warned = #Warnings > 0
    RestoreWarnings()
    lu.assertTrue(warned)
end

function TestString:testDrawUsesInputText()
    local field = {
        type = "string",
        configKey = "Label",
        label = "Label",
        default = "",
        maxLen = 32,
        _imguiId = "##Label",
        _maxLen = 32,
    }
    local seen = {}
    local imgui = {
        Text = function(label)
            seen.label = label
        end,
        IsItemHovered = function() return false end,
        SameLine = function() end,
        PushItemWidth = function(width)
            seen.width = width
        end,
        PopItemWidth = function() end,
        InputText = function(id, value, maxLen)
            seen.id = id
            seen.value = value
            seen.maxLen = maxLen
            return "Updated", true
        end,
    }

    local nextValue, changed = lib.FieldTypes.string.draw(imgui, field, "Current", 220)

    lu.assertEquals(seen.label, "Label")
    lu.assertEquals(seen.id, "##Label")
    lu.assertEquals(seen.value, "Current")
    lu.assertEquals(seen.maxLen, 32)
    lu.assertEquals(seen.width, 220)
    lu.assertEquals(nextValue, "Updated")
    lu.assertTrue(changed)
end

TestDropdown = {}

local dropdownField = {
    type = "dropdown",
    configKey = "Mode",
    values = { "Vanilla", "Always", "Never" },
    default = "Vanilla",
}

function TestDropdown:testToHash()
    lu.assertEquals(lib.FieldTypes.dropdown.toHash(dropdownField, "Always"), "Always")
end

function TestDropdown:testFromHash()
    lu.assertEquals(lib.FieldTypes.dropdown.fromHash(dropdownField, "Always"), "Always")
end

function TestDropdown:testRoundTrip()
    for _, v in ipairs(dropdownField.values) do
        lu.assertEquals(lib.FieldTypes.dropdown.fromHash(dropdownField,
            lib.FieldTypes.dropdown.toHash(dropdownField, v)), v)
    end
end

function TestDropdown:testToStaging()
    lu.assertEquals(lib.FieldTypes.dropdown.toStaging("Always"), "Always")
end

function TestDropdown:testFromHashUnknownValueFallsBackToDefault()
    lu.assertEquals(lib.FieldTypes.dropdown.fromHash(dropdownField, "OldRemovedValue"), "Vanilla")
end

function TestDropdown:testValidateWarnsPipeInValue()
    local field = { type = "dropdown", configKey = "X", values = { "Good", "Bad|Value" } }
    CaptureWarnings()
    lib.FieldTypes.dropdown.validate(field, "test")
    local warned = #Warnings > 0
    RestoreWarnings()
    lu.assertTrue(warned)
end

function TestDropdown:testValidateWarnsBadDisplayValues()
    local field = { type = "dropdown", configKey = "X", values = { "A" }, displayValues = "bad" }
    CaptureWarnings()
    lib.FieldTypes.dropdown.validate(field, "test")
    local warned = #Warnings > 0
    RestoreWarnings()
    lu.assertTrue(warned)
end

-- =============================================================================
-- RADIO
-- =============================================================================

TestRadio = {}

local radioField = {
    type = "radio",
    configKey = "Speed",
    values = { "Slow", "Normal", "Fast" },
    default = "Normal",
}

function TestRadio:testToHash()
    lu.assertEquals(lib.FieldTypes.radio.toHash(radioField, "Fast"), "Fast")
end

function TestRadio:testFromHash()
    lu.assertEquals(lib.FieldTypes.radio.fromHash(radioField, "Fast"), "Fast")
end

function TestRadio:testRoundTrip()
    for _, v in ipairs(radioField.values) do
        lu.assertEquals(lib.FieldTypes.radio.fromHash(radioField,
            lib.FieldTypes.radio.toHash(radioField, v)), v)
    end
end

function TestRadio:testFromHashUnknownValueFallsBackToDefault()
    lu.assertEquals(lib.FieldTypes.radio.fromHash(radioField, "OldRemovedValue"), "Normal")
end

function TestRadio:testValidateWarnsPipeInValue()
    local field = { type = "radio", configKey = "X", values = { "Good", "Bad|Value" } }
    CaptureWarnings()
    lib.FieldTypes.radio.validate(field, "test")
    local warned = #Warnings > 0
    RestoreWarnings()
    lu.assertTrue(warned)
end

function TestRadio:testValidateWarnsBadDisplayValues()
    local field = { type = "radio", configKey = "X", values = { "A" }, displayValues = "bad" }
    CaptureWarnings()
    lib.FieldTypes.radio.validate(field, "test")
    local warned = #Warnings > 0
    RestoreWarnings()
    lu.assertTrue(warned)
end

TestChoiceDisplay = {}

function TestChoiceDisplay:testDropdownUsesDisplayValuesForPreviewAndOptions()
    local field = {
        type = "dropdown",
        configKey = "Mode",
        values = { "", "ZeusUpgrade" },
        displayValues = { [""] = "None", ZeusUpgrade = "Zeus" },
        _imguiId = "##Mode",
    }
    local seen = {}
    local imgui = {
        Text = function() end,
        IsItemHovered = function() return false end,
        SameLine = function() end,
        PushItemWidth = function() end,
        PopItemWidth = function() end,
        BeginCombo = function(_, preview)
            seen.preview = preview
            return true
        end,
        Selectable = function(label)
            table.insert(seen, label)
            return false
        end,
        EndCombo = function() end,
    }

    lib.FieldTypes.dropdown.draw(imgui, field, "ZeusUpgrade")

    lu.assertEquals(seen.preview, "Zeus")
    lu.assertEquals(seen[1], "None")
    lu.assertEquals(seen[2], "Zeus")
end

function TestChoiceDisplay:testRadioUsesDisplayValuesForLabels()
    local field = {
        type = "radio",
        configKey = "Mode",
        values = { "", "ZeusUpgrade" },
        displayValues = { [""] = "None", ZeusUpgrade = "Zeus" },
    }
    local seen = {}
    local imgui = {
        Text = function() end,
        IsItemHovered = function() return false end,
        RadioButton = function(label)
            table.insert(seen, label)
            return false
        end,
        SameLine = function() end,
        NewLine = function() end,
    }

    lib.FieldTypes.radio.draw(imgui, field, "ZeusUpgrade")

    lu.assertEquals(seen[1], "None")
    lu.assertEquals(seen[2], "Zeus")
end

-- =============================================================================
-- INT32
-- =============================================================================

TestInt32 = {}

local int32Field = {
    type = "int32",
    configKey = "PackedValue",
    default = 0,
}

function TestInt32:testToHash()
    lu.assertEquals(lib.FieldTypes.int32.toHash(int32Field, 17), "17")
end

function TestInt32:testFromHash()
    lu.assertEquals(lib.FieldTypes.int32.fromHash(int32Field, "17"), 17)
end

function TestInt32:testFromHashBadInputFallsBackToDefault()
    lu.assertEquals(lib.FieldTypes.int32.fromHash(int32Field, "bad"), 0)
end

function TestInt32:testToStaging()
    lu.assertEquals(lib.FieldTypes.int32.toStaging("42", int32Field), 42)
end

-- =============================================================================
-- STEPPER
-- =============================================================================

TestStepper = {}

local stepperField = {
    type = "stepper",
    configKey = "Count",
    default = 4,
    min = 1,
    max = 9,
    step = 1,
}

function TestStepper:testToHash()
    lu.assertEquals(lib.FieldTypes.stepper.toHash(stepperField, 6), "6")
end

function TestStepper:testFromHash()
    lu.assertEquals(lib.FieldTypes.stepper.fromHash(stepperField, "6"), 6)
end

function TestStepper:testFromHashClampsBelowMin()
    lu.assertEquals(lib.FieldTypes.stepper.fromHash(stepperField, "0"), 1)
end

function TestStepper:testFromHashClampsAboveMax()
    lu.assertEquals(lib.FieldTypes.stepper.fromHash(stepperField, "99"), 9)
end

function TestStepper:testToStagingClamps()
    lu.assertEquals(lib.FieldTypes.stepper.toStaging("99", stepperField), 9)
end

function TestStepper:testValidateWarnsWhenMinExceedsMax()
    local field = {
        type = "stepper",
        configKey = "Bad",
        default = 3,
        min = 10,
        max = 1,
    }
    CaptureWarnings()
    lib.FieldTypes.stepper.validate(field, "test")
    local warned = #Warnings > 0
    RestoreWarnings()
    lu.assertTrue(warned)
end

-- =============================================================================
-- FIELD VISIBILITY
-- =============================================================================

TestFieldVisibility = {}

function TestFieldVisibility:testVisibleWithoutGate()
    lu.assertTrue(lib.isFieldVisible({ configKey = "X" }, { X = false }))
end

function TestFieldVisibility:testVisibleWhenGateTrue()
    lu.assertTrue(lib.isFieldVisible({ configKey = "X", visibleIf = "Enabled" }, { Enabled = true }))
end

function TestFieldVisibility:testHiddenWhenGateFalse()
    lu.assertFalse(lib.isFieldVisible({ configKey = "X", visibleIf = "Enabled" }, { Enabled = false }))
end

function TestFieldVisibility:testHiddenWhenGateMissing()
    lu.assertFalse(lib.isFieldVisible({ configKey = "X", visibleIf = "Enabled" }, {}))
end

-- =============================================================================
-- SEPARATOR / LAYOUT
-- =============================================================================

TestLayoutFields = {}

function TestLayoutFields:testSeparatorAllowsMissingConfigKey()
    CaptureWarnings()
    lib.validateSchema({
        { type = "separator", label = "Group" },
    }, "test")
    local warned = #Warnings > 0
    RestoreWarnings()
    lu.assertFalse(warned)
end

function TestLayoutFields:testIndentWarnsWhenNotBoolean()
    CaptureWarnings()
    lib.validateSchema({
        { type = "checkbox", configKey = "Enabled", default = false, indent = 1 },
    }, "test")
    local warned = #Warnings > 0
    RestoreWarnings()
    lu.assertTrue(warned)
end

TestFieldTypeValidation = {}

function TestFieldTypeValidation:testValidateFieldTypesErrorsOnMissingRequiredMethods()
    local original = lib.FieldTypes.customBroken
    lib.FieldTypes.customBroken = {
        validate = function() end,
        draw = function() end,
    }

    local ok, err = pcall(lib.validateFieldTypes)
    lib.FieldTypes.customBroken = original

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "field type 'customBroken' is missing required method 'toHash'")
end

function TestFieldTypeValidation:testValidateSchemaErrorsOnBrokenRegisteredFieldType()
    local original = lib.FieldTypes.customBroken
    lib.FieldTypes.customBroken = {
        validate = function() end,
        draw = function() end,
    }

    local schema = {
        { type = "customBroken", configKey = "Broken", default = false },
        { type = "checkbox", configKey = "Good", default = false },
    }

    local ok, err = pcall(lib.validateSchema, schema, "BrokenTypeMod")
    lib.FieldTypes.customBroken = original

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "field type 'customBroken' is missing required method 'toHash'")
end
