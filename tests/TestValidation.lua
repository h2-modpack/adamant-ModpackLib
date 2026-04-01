local lu = require('luaunit')

TestValidateSchema = {}

function TestValidateSchema:setUp()
    CaptureWarnings()
end

function TestValidateSchema:tearDown()
    RestoreWarnings()
end

function TestValidateSchema:testValidSchemaNoWarnings()
    local schema = {
        { type = "checkbox", configKey = "A" },
        { type = "dropdown", configKey = "B", values = { "X", "Y" } },
    }
    lib.validateSchema(schema, "TestMod")
    lu.assertEquals(#Warnings, 0)
end

function TestValidateSchema:testMissingConfigKey()
    local schema = {
        { type = "checkbox" },
    }
    lib.validateSchema(schema, "TestMod")
    lu.assertTrue(#Warnings > 0)
    lu.assertStrContains(Warnings[1], "missing configKey")
end

function TestValidateSchema:testMissingType()
    local schema = {
        { configKey = "A" },
    }
    lib.validateSchema(schema, "TestMod")
    lu.assertTrue(#Warnings > 0)
    lu.assertStrContains(Warnings[1], "missing type")
end

function TestValidateSchema:testUnknownType()
    local schema = {
        { type = "slider", configKey = "A" },
    }
    lib.validateSchema(schema, "TestMod")
    lu.assertTrue(#Warnings > 0)
    lu.assertStrContains(Warnings[1], "unknown type")
    lu.assertEquals(#(schema._configFields or {}), 0)
end

function TestValidateSchema:testUnknownTypeExcludedFromConfigFields()
    local schema = {
        { type = "checkbox", configKey = "Good" },
        { type = "slider", configKey = "Bad" },
    }
    lib.validateSchema(schema, "TestMod")
    lu.assertEquals(#(schema._configFields or {}), 1)
    lu.assertEquals(schema._configFields[1].configKey, "Good")
end

function TestValidateSchema:testDropdownMissingValues()
    local schema = {
        { type = "dropdown", configKey = "A" },
    }
    lib.validateSchema(schema, "TestMod")
    lu.assertTrue(#Warnings > 0)
    lu.assertStrContains(Warnings[1], "missing values")
end

function TestValidateSchema:testDropdownEmptyValues()
    local schema = {
        { type = "dropdown", configKey = "A", values = {} },
    }
    lib.validateSchema(schema, "TestMod")
    lu.assertTrue(#Warnings > 0)
    lu.assertStrContains(Warnings[1], "non-empty list")
end

function TestValidateSchema:testRadioMissingValues()
    local schema = {
        { type = "radio", configKey = "A" },
    }
    lib.validateSchema(schema, "TestMod")
    lu.assertTrue(#Warnings > 0)
    lu.assertStrContains(Warnings[1], "missing values")
end

function TestValidateSchema:testNotATable()
    lib.validateSchema("not a table", "TestMod")
    lu.assertTrue(#Warnings > 0)
    lu.assertStrContains(Warnings[1], "not a table")
end

function TestValidateSchema:testVisibleIfWarnsWhenNotInSameSchema()
    local schema = {
        { type = "checkbox", configKey = "Enabled", default = false },
        { type = "checkbox", configKey = "Strict", default = false, visibleIf = "OtherModuleFlag" },
    }
    lib.validateSchema(schema, "TestMod")
    lu.assertTrue(#Warnings > 0)
    lu.assertStrContains(table.concat(Warnings, "\n"), "visibleIf 'OtherModuleFlag'")
end
