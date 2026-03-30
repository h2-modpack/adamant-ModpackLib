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
