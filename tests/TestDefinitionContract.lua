local lu = require('luaunit')

TestDefinitionContract = {}

function TestDefinitionContract:setUp()
    CaptureWarnings()
end

function TestDefinitionContract:tearDown()
    RestoreWarnings()
end

function TestDefinitionContract:testCreateStoreWarnsOnUnknownTopLevelDefinitionKey()
    lib.store.create({}, {
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        ui = {},
        affectRunData = true,
    })

    lu.assertEquals(#Warnings, 2)
    lu.assertStrContains(Warnings[1], "unknown definition key 'affectRunData'")
    lu.assertStrContains(Warnings[2], "definition.ui is ignored")
end

function TestDefinitionContract:testValidateDefinitionWarnsOnSpecialFieldsThatFrameworkIgnores()
    lib.store.create({}, {
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

    lu.assertEquals(#Warnings, 3)
    lu.assertStrContains(Warnings[1], "definition.category is ignored")
    lu.assertStrContains(Warnings[2], "definition.subgroup is ignored")
    lu.assertStrContains(Warnings[3], "definition.selectQuickUi is ignored")
end

function TestDefinitionContract:testValidateDefinitionWarnsOnIncompleteLifecycle()
    lib.store.create({}, {
        id = "Example",
        name = "Example",
        affectsRunData = true,
        apply = function() end,
    })

    lu.assertEquals(#Warnings, 2)
    lu.assertStrContains(Warnings[1], "manual lifecycle requires both definition.apply and definition.revert")
    lu.assertStrContains(Warnings[2], "affectsRunData=true")
end
