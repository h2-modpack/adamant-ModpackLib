local lu = require('luaunit')

TestDefinitionContract = {}

function TestDefinitionContract:setUp()
    CaptureWarnings()
end

function TestDefinitionContract:tearDown()
    RestoreWarnings()
end

function TestDefinitionContract:testCreateStoreWarnsOnUnknownTopLevelDefinitionKey()
    lib.createStore({}, {
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        ui = {},
        affectRunData = true,
    })

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "unknown definition key 'affectRunData'")
end

function TestDefinitionContract:testValidateDefinitionWarnsOnSpecialFieldsThatFrameworkIgnores()
    lib.validateDefinition({
        modpack = "test-pack",
        special = true,
        name = "Example Special",
        category = "Run Mods",
        subgroup = "General",
        selectQuickUi = function() end,
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
    }, "Example Special")

    lu.assertEquals(#Warnings, 3)
    lu.assertStrContains(Warnings[1], "special modules ignore definition.category")
    lu.assertStrContains(Warnings[2], "special modules ignore definition.subgroup")
    lu.assertStrContains(Warnings[3], "special modules ignore definition.selectQuickUi")
end

function TestDefinitionContract:testValidateDefinitionWarnsOnIncompleteLifecycle()
    lib.validateDefinition({
        id = "Example",
        name = "Example",
        affectsRunData = true,
        apply = function() end,
    }, "Example")

    lu.assertEquals(#Warnings, 2)
    lu.assertStrContains(Warnings[1], "manual lifecycle requires both definition.apply and definition.revert")
    lu.assertStrContains(Warnings[2], "affectsRunData=true")
end
