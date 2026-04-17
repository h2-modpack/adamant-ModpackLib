local lu = require('luaunit')

TestStorageValidation = {}

function TestStorageValidation:setUp()
    CaptureWarnings()
end

function TestStorageValidation:tearDown()
    RestoreWarnings()
end

function TestStorageValidation:testDuplicateAliasWarns()
    lib.storage.validate({
        { type = "bool", alias = "Flag", configKey = "FlagA", default = false },
        { type = "bool", alias = "Flag", configKey = "FlagB", default = false },
    }, "DuplicateAlias")

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "duplicate alias 'Flag'")
end

function TestStorageValidation:testDuplicateConfigKeyWarns()
    lib.storage.validate({
        { type = "bool", alias = "FlagA", configKey = "Shared", default = false },
        { type = "bool", alias = "FlagB", configKey = "Shared", default = false },
    }, "DuplicateKey")

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "duplicate configKey 'Shared'")
end

function TestStorageValidation:testTransientRootRegistersAliasButNotPersistedRoots()
    local storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
        { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 },
    }

    lib.storage.validate(storage, "TransientRoot")

    lu.assertEquals(#lib.storage.getRoots(storage), 1)
    lu.assertEquals(lib.storage.getRoots(storage)[1].alias, "Enabled")
    lu.assertNotNil(lib.storage.getAliases(storage).FilterText)
    lu.assertEquals(#Warnings, 0)
end

function TestStorageValidation:testPackedIntDerivesChildAliasesAndDefault()
    local storage = {
        {
            type = "packedInt",
            alias = "Packed",
            configKey = "Packed",
            bits = {
                { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = true },
                { alias = "ModeBits", offset = 1, width = 2, type = "int", default = 2 },
            },
        },
    }

    lib.storage.validate(storage, "PackedTest")

    lu.assertEquals(storage[1].default, 5)
    lu.assertNotNil(lib.storage.getAliases(storage).EnabledBit)
    lu.assertNotNil(lib.storage.getAliases(storage).ModeBits)
    lu.assertEquals(#Warnings, 0)
end

function TestStorageValidation:testBoolStorageRoundTripsHash()
    local node = { type = "bool", alias = "Enabled", configKey = "Enabled", default = false }
    local storage = { node }
    lib.storage.validate(storage, "BoolHash")

    lu.assertEquals(lib.storage.toHash(node, true), "1")
    lu.assertTrue(lib.storage.fromHash(node, "1"))
    lu.assertFalse(lib.storage.fromHash(node, "0"))
end
