local lu = require('luaunit')

local function assertWarningContains(fragment)
    for _, warning in ipairs(Warnings) do
        if string.find(warning, fragment, 1, true) then
            return
        end
    end
    lu.fail("expected warning containing '" .. fragment .. "'")
end

TestStorageValidation = {}

function TestStorageValidation:setUp()
    CaptureWarnings()
end

function TestStorageValidation:tearDown()
    RestoreWarnings()
end

function TestStorageValidation:testDuplicateAliasWarns()
    lib.validateStorage({
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
        { type = "bool", alias = "Enabled", configKey = "OtherEnabled", default = false },
    }, "DupAlias")

    assertWarningContains("duplicate alias 'Enabled'")
end

function TestStorageValidation:testDuplicateConfigKeyWarns()
    lib.validateStorage({
        { type = "bool", alias = "EnabledA", configKey = "Enabled", default = false },
        { type = "bool", alias = "EnabledB", configKey = "Enabled", default = false },
    }, "DupKey")

    assertWarningContains("duplicate configKey 'Enabled'")
end

function TestStorageValidation:testRootAliasDefaultsToConfigKey()
    local storage = {
        { type = "bool", configKey = "Enabled", default = false },
    }

    lib.validateStorage(storage, "AliasDefault")

    local aliases = lib.getStorageAliases(storage)
    lu.assertNotNil(aliases.Enabled)
    lu.assertEquals(aliases.Enabled.configKey, "Enabled")
end

function TestStorageValidation:testPackedOverlapWarns()
    lib.validateStorage({
        {
            type = "packedInt",
            alias = "Packed",
            configKey = "Packed",
            bits = {
                { alias = "FlagA", offset = 0, width = 2, type = "int", default = 0 },
                { alias = "FlagB", offset = 1, width = 2, type = "int", default = 0 },
            },
        },
    }, "Overlap")

    assertWarningContains("packed bit overlaps bit 1")
end

function TestStorageValidation:testPackedAliasMatchingExistingRootAliasWarns()
    lib.validateStorage({
        { type = "bool", alias = "Mode", configKey = "Mode", default = false },
        {
            type = "packedInt",
            alias = "Packed",
            configKey = "Packed",
            bits = {
                { alias = "Mode", offset = 0, width = 1, type = "bool", default = true },
            },
        },
    }, "Conflict")

    assertWarningContains("duplicate alias 'Mode'")
end

TestUiValidation = {}

function TestUiValidation:setUp()
    CaptureWarnings()
end

function TestUiValidation:tearDown()
    RestoreWarnings()
end

function TestUiValidation:testWidgetStorageTypeMismatchWarns()
    local storage = {
        { type = "int", alias = "Count", configKey = "Count", default = 2, min = 1, max = 5 },
    }
    lib.validateStorage(storage, "WidgetType")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Count" }, label = "Count" },
    }, "WidgetType", storage)

    assertWarningContains("bound alias 'Count' is int, expected bool")
end

function TestUiValidation:testVisibleIfRequiresBoolAlias()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
    }
    lib.validateStorage(storage, "VisibleIf")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = "Mode" },
    }, "VisibleIf", storage)

    assertWarningContains("visibleIf alias 'Mode' must resolve to bool storage")
end

function TestUiValidation:testUnknownVisibleIfAliasWarns()
    local storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
    }
    lib.validateStorage(storage, "VisibleIfMissing")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = "MissingGate" },
    }, "VisibleIfMissing", storage)

    assertWarningContains("visibleIf alias 'MissingGate' does not exist")
end

function TestUiValidation:testVisibleIfValueSupportsNonBoolAliases()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
    }
    lib.validateStorage(storage, "VisibleIfValue")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = { alias = "Mode", value = "Forced" } },
    }, "VisibleIfValue", storage)

    lu.assertEquals(#Warnings, 0)
end

function TestUiValidation:testVisibleIfAnyOfRequiresNonEmptyList()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
    }
    lib.validateStorage(storage, "VisibleIfAnyOf")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = { alias = "Mode", anyOf = {} } },
    }, "VisibleIfAnyOf", storage)

    assertWarningContains("visibleIf.anyOf must be a non-empty list")
end

function TestUiValidation:testVisibleIfRejectsValueAndAnyOfTogether()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
    }
    lib.validateStorage(storage, "VisibleIfConflict")

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = { alias = "Mode", value = "Forced", anyOf = { "Forced" } } },
    }, "VisibleIfConflict", storage)

    assertWarningContains("visibleIf cannot specify both value and anyOf")
end

function TestUiValidation:testLayoutChildrenValidateRecursively()
    local storage = {
        { type = "bool", alias = "Gate", configKey = "Gate", default = true },
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
    }
    lib.validateStorage(storage, "Layout")

    lib.validateUi({
        {
            type = "group",
            label = "Outer",
            children = {
                { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = "Gate" },
            },
        },
    }, "Layout", storage)

    lu.assertEquals(#Warnings, 0)
end

function TestUiValidation:testPrepareUiNodeValidatesAgainstRawStorage()
    local storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
    }
    local node = { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" }

    lib.prepareUiNode(node, "PrepareRaw", storage)

    lu.assertEquals(#Warnings, 0)
    local aliases = lib.getStorageAliases(storage)
    lu.assertNotNil(aliases.Enabled)
end

function TestUiValidation:testPrepareUiNodeWarnsUnknownAliasAgainstRawStorage()
    local storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
    }
    local node = { type = "checkbox", binds = { value = "Missing" }, label = "Enabled" }

    lib.prepareUiNode(node, "PrepareRawMissing", storage)

    assertWarningContains("binds.value unknown alias 'Missing'")
end

function TestUiValidation:testValidateUiAcceptsRawStorage()
    local storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
    }

    lib.validateUi({
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
    }, "ValidateRaw", storage)

    lu.assertEquals(#Warnings, 0)
end

function TestUiValidation:testWidgetGeometryRejectsUnknownKeys()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "A" },
    }
    lib.validateStorage(storage, "Geometry")

    lib.validateUi({
        {
            type = "dropdown",
            binds = { value = "Mode" },
            label = "Mode",
            values = { "A", "B" },
            geometry = {
                controlStart = 120,
                slots = {
                    { name = "control", start = 120 },
                },
            },
        },
    }, "Geometry", storage)

    assertWarningContains("geometry key 'controlStart' is not supported; geometry only supports 'slots'")
end

function TestUiValidation:testCustomWidgetGeometryIsValidated()
    local storage = {
        { type = "int", alias = "Count", configKey = "Count", default = 2, min = 1, max = 5 },
    }
    lib.validateStorage(storage, "CustomGeometry")

    lib.validateUi({
        {
            type = "fancyStepper",
            binds = { value = "Count" },
            geometry = {
                slots = {
                    { name = "control", start = 120 },
                },
            },
        },
    }, "CustomGeometry", storage, {
        widgets = {
            fancyStepper = {
                binds = { value = { storageType = "int" } },
                slots = { "control" },
                validate = function() end,
                draw = function() end,
            },
        },
    })

    lu.assertEquals(#Warnings, 0)
end

function TestUiValidation:testMergeCustomTypesCachesByTableIdentity()
    local mergeCustomTypes = AdamantModpackLib_Internal.shared.fieldRegistry.MergeCustomTypes
    local customTypes = {
        widgets = {
            fancyStepper = {
                binds = { value = { storageType = "int" } },
                slots = { "control" },
                validate = function() end,
                draw = function() end,
            },
        },
        layouts = {
            fancyPanel = {
                validate = function() end,
                render = function() return true end,
            },
        },
    }

    local widgetsA, layoutsA = mergeCustomTypes(customTypes)
    local widgetsB, layoutsB = mergeCustomTypes(customTypes)

    lu.assertIs(widgetsA, widgetsB)
    lu.assertIs(layoutsA, layoutsB)
    lu.assertNotNil(widgetsA.fancyStepper)
    lu.assertNotNil(layoutsA.fancyPanel)
end

function TestUiValidation:testValueAlignRequiresKnownAlignment()
    local storage = {
        { type = "int", alias = "Count", configKey = "Count", default = 2, min = 1, max = 5 },
    }
    lib.validateStorage(storage, "ValueAlign")

    lib.validateUi({
        {
            type = "stepper",
            binds = { value = "Count" },
            label = "Count",
            min = 1,
            max = 5,
            geometry = {
                slots = {
                    { name = "value", align = "middle" },
                },
            },
        },
    }, "ValueAlign", storage)

    assertWarningContains("geometry.slots[1].align must be one of 'center' or 'right'")
end

function TestUiValidation:testValueAlignRequiresValueWidth()
    local storage = {
        { type = "int", alias = "Count", configKey = "Count", default = 2, min = 1, max = 5 },
    }
    lib.validateStorage(storage, "ValueWidthRequired")

    lib.validateUi({
        {
            type = "stepper",
            binds = { value = "Count" },
            label = "Count",
            min = 1,
            max = 5,
            geometry = {
                slots = {
                    { name = "value", align = "center" },
                },
            },
        },
    }, "ValueWidthRequired", storage)

    assertWarningContains("geometry.slots[1].align requires width on the same slot")
end

function TestUiValidation:testDuplicateSlotGeometryWarns()
    local storage = {
        { type = "int", alias = "Count", configKey = "Count", default = 2, min = 1, max = 5 },
    }
    lib.validateStorage(storage, "DuplicateSlotGeometry")

    lib.validateUi({
        {
            type = "stepper",
            binds = { value = "Count" },
            label = "Count",
            min = 1,
            max = 5,
            geometry = {
                slots = {
                    { name = "value", start = 20, width = 24, align = "center" },
                    { name = "value", start = 40, width = 24, align = "center" },
                },
            },
        },
    }, "DuplicateSlotGeometry", storage)

    assertWarningContains("geometry slot 'value' is declared more than once")
end

function TestUiValidation:testNegativeGeometryStartWarns()
    local storage = {
        { type = "int", alias = "Count", configKey = "Count", default = 2, min = 1, max = 5 },
    }
    lib.validateStorage(storage, "NegativeGeometry")

    lib.validateUi({
        {
            type = "stepper",
            binds = { value = "Count" },
            label = "Count",
            min = 1,
            max = 5,
            geometry = {
                slots = {
                    { name = "decrement", start = -10 },
                },
            },
        },
    }, "NegativeGeometry", storage)

    assertWarningContains("geometry.slots[1].start must be a non-negative number")
end

function TestUiValidation:testSlotLineMustBePositiveInteger()
    local storage = {
        { type = "int", alias = "Count", configKey = "Count", default = 2, min = 1, max = 5 },
    }
    lib.validateStorage(storage, "SlotLine")

    lib.validateUi({
        {
            type = "stepper",
            binds = { value = "Count" },
            label = "Count",
            min = 1,
            max = 5,
            geometry = {
                slots = {
                    { name = "value", line = 1.5, width = 24, align = "center" },
                },
            },
        },
    }, "SlotLine", storage)

    assertWarningContains("geometry.slots[1].line must be a positive integer")
end

function TestUiValidation:testRadioOptionSlotMustBeInRange()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "A" },
    }
    lib.validateStorage(storage, "RadioOptionSlot")

    lib.validateUi({
        {
            type = "radio",
            binds = { value = "Mode" },
            label = "Mode",
            values = { "A", "B" },
            geometry = {
                slots = {
                    { name = "option:3", line = 1, start = 0 },
                },
            },
        },
    }, "RadioOptionSlot", storage)

    assertWarningContains("geometry slot 'option:3' is out of range for 2 radio options")
end

function TestUiValidation:testRadioWarnsWhenWidthOrAlignAreIgnoredByOptionSlots()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "A" },
    }
    lib.validateStorage(storage, "RadioIgnoredGeometry")

    lib.validateUi({
        {
            type = "radio",
            binds = { value = "Mode" },
            label = "",
            values = { "A", "B" },
            geometry = {
                slots = {
                    { name = "option:1", start = 0, width = 80, align = "right" },
                },
            },
        },
    }, "RadioIgnoredGeometry", storage)

    assertWarningContains("geometry slot 'option:1' width is ignored by widget type 'radio'")
    assertWarningContains("geometry slot 'option:1' align is ignored by widget type 'radio'")
end

function TestUiValidation:testCustomWidgetDynamicSlotsCanValidateNames()
    local storage = {
        { type = "int", alias = "Count", configKey = "Count", default = 2, min = 1, max = 5 },
    }
    lib.validateStorage(storage, "CustomDynamicSlots")

    lib.validateUi({
        {
            type = "fancyWidget",
            binds = { value = "Count" },
            geometry = {
                slots = {
                    { name = "item:3", line = 1, start = 0 },
                },
            },
        },
    }, "CustomDynamicSlots", storage, {
        widgets = {
            fancyWidget = {
                binds = { value = { storageType = "int" } },
                slots = { "label" },
                dynamicSlots = function(_, slotName)
                    local idx = type(slotName) == "string" and tonumber(string.match(slotName, "^item:(%d+)$")) or nil
                    if idx == nil then
                        return false, nil
                    end
                    if idx > 2 then
                        return false, ("geometry slot '%s' exceeds declared item count"):format(slotName)
                    end
                    return true, nil
                end,
                validate = function() end,
                draw = function() end,
            },
        },
    })

    assertWarningContains("geometry slot 'item:3' exceeds declared item count")
end

function TestUiValidation:testPackedCheckboxListSlotCountMustBePositiveInteger()
    local storage = {
        {
            type = "packedInt",
            alias = "PackedFlags",
            configKey = "PackedFlags",
            bits = {
                { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false },
            },
        },
    }
    lib.validateStorage(storage, "PackedSlotCount")

    lib.validateUi({
        {
            type = "packedCheckboxList",
            binds = { value = "PackedFlags" },
            slotCount = 1.5,
        },
    }, "PackedSlotCount", storage)

    assertWarningContains("packedCheckboxList slotCount must be a positive integer")
end

function TestUiValidation:testPackedCheckboxListItemSlotMustBeWithinDeclaredSlotCount()
    local storage = {
        {
            type = "packedInt",
            alias = "PackedFlags",
            configKey = "PackedFlags",
            bits = {
                { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false },
            },
        },
    }
    lib.validateStorage(storage, "PackedItemSlot")

    lib.validateUi({
        {
            type = "packedCheckboxList",
            binds = { value = "PackedFlags" },
            slotCount = 2,
            geometry = {
                slots = {
                    { name = "item:3", line = 1, start = 0 },
                },
            },
        },
    }, "PackedItemSlot", storage)

    assertWarningContains("geometry slot 'item:3' is out of range for packedCheckboxList slotCount 2")
end

function TestUiValidation:testPackedCheckboxListUsesDefaultSlotCountWhenOmitted()
    local storage = {
        {
            type = "packedInt",
            alias = "PackedFlags",
            configKey = "PackedFlags",
            bits = {
                { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false },
            },
        },
    }
    lib.validateStorage(storage, "PackedImplicitSlotCount")

    lib.validateUi({
        {
            type = "packedCheckboxList",
            binds = { value = "PackedFlags" },
            geometry = {
                slots = {
                    { name = "item:33", line = 1, start = 0 },
                },
            },
        },
    }, "PackedImplicitSlotCount", storage)

    assertWarningContains("geometry slot 'item:33' is out of range for packedCheckboxList slotCount 32")
end

function TestUiValidation:testPackedCheckboxListWarnsWhenWidthOrAlignAreIgnoredByItemSlots()
    local storage = {
        {
            type = "packedInt",
            alias = "PackedFlags",
            configKey = "PackedFlags",
            bits = {
                { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false },
                { alias = "FlagB", offset = 1, width = 1, type = "bool", default = false },
            },
        },
    }
    lib.validateStorage(storage, "PackedIgnoredGeometry")

    lib.validateUi({
        {
            type = "packedCheckboxList",
            binds = { value = "PackedFlags" },
            slotCount = 2,
            geometry = {
                slots = {
                    { name = "item:1", line = 1, start = 0, width = 100, align = "center" },
                },
            },
        },
    }, "PackedIgnoredGeometry", storage)

    assertWarningContains("geometry slot 'item:1' width is ignored by widget type 'packedCheckboxList'")
    assertWarningContains("geometry slot 'item:1' align is ignored by widget type 'packedCheckboxList'")
end

function TestUiValidation:testPanelChildColumnMustExist()
    local storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "A" },
    }
    lib.validateStorage(storage, "PanelColumn")

    lib.validateUi({
        {
            type = "panel",
            columns = {
                { name = "left", start = 0, width = 100 },
            },
            children = {
                {
                    type = "dropdown",
                    binds = { value = "Mode" },
                    values = { "A", "B" },
                    panel = { column = "right", line = 1, slots = { "control" } },
                },
            },
        },
    }, "PanelColumn", storage)

    assertWarningContains("panel.column references unknown column 'right'")
end
