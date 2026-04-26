local lu = require('luaunit')

TestDefinitionContract = {}

function TestDefinitionContract:setUp()
    CaptureWarnings()
end

function TestDefinitionContract:tearDown()
    RestoreWarnings()
end

function TestDefinitionContract:testCreateStoreWarnsOnUnknownTopLevelDefinitionKey()
    lib.prepareDefinition({}, {
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        ui = {},
        affectRunData = true,
    })

    local joined = table.concat(Warnings, "\n")
    lu.assertEquals(#Warnings, 2)
    lu.assertStrContains(joined, "unknown definition key 'ui'")
    lu.assertStrContains(joined, "unknown definition key 'affectRunData'")
end

function TestDefinitionContract:testValidateDefinitionWarnsOnOldVocabularyKeysAsUnknown()
    lib.prepareDefinition({}, {
        modpack = "test-pack",
        id = "ExampleSpecial",
        name = "Example Special",
        category = "Run Mods",
        subgroup = "General",
        selectQuickUi = function() end,
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
    })

    local joined = table.concat(Warnings, "\n")
    lu.assertEquals(#Warnings, 3)
    lu.assertStrContains(joined, "unknown definition key 'category'")
    lu.assertStrContains(joined, "unknown definition key 'subgroup'")
    lu.assertStrContains(joined, "unknown definition key 'selectQuickUi'")
end

function TestDefinitionContract:testValidateDefinitionWarnsOnIncompleteLifecycle()
    lib.prepareDefinition({}, {
        id = "Example",
        name = "Example",
        affectsRunData = true,
        apply = function() end,
    })

    lu.assertEquals(#Warnings, 2)
    lu.assertStrContains(Warnings[1], "manual lifecycle requires both definition.apply and definition.revert")
    lu.assertStrContains(Warnings[2], "affectsRunData=true")
end

