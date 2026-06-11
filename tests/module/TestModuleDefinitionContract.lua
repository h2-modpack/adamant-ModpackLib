local lu = require("luaunit")
local createManagedModuleHarness = require("tests/harness/create_managed_module_harness")

TestModuleDefinitionContract = {}

function TestModuleDefinitionContract:setUp()
    self.h = createManagedModuleHarness()
    self.h:captureWarnings()
end

function TestModuleDefinitionContract:tearDown()
    self.h:restoreWarnings()
end

function TestModuleDefinitionContract:testCreateStoreErrorsOnUnknownTopLevelDefinitionKey()
    lu.assertErrorMsgContains("unknown definition key 'ui'", function()
        self.h:prepareDefinition({}, {
            id = "Example",
            name = "Example",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            ui = {},
        })
    end)
end

function TestModuleDefinitionContract:testValidateDefinitionErrorsOnOldVocabularyKeysAsUnknown()
    lu.assertErrorMsgContains("unknown definition key 'category'", function()
        self.h:prepareDefinition({}, {
            modpack = "test-pack",
            id = "ExampleSpecial",
            name = "Example Special",
            category = "Run Mods",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
        })
    end)
end

function TestModuleDefinitionContract:testPrepareDefinitionRejectsBehaviorFieldsAsUnknownKeys()
    lu.assertErrorMsgContains("unknown definition key 'affectsRunData'", function()
        self.h:prepareDefinition({}, {
            id = "Example",
            name = "Example",
            affectsRunData = true,
        })
    end)

    lu.assertErrorMsgContains("unknown definition key 'apply'", function()
        self.h:prepareDefinition({}, {
            id = "Example",
            name = "Example",
            apply = function() end,
        })
    end)
end
