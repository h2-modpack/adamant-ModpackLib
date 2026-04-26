local lu = require('luaunit')

TestStorageValidation = {}

function TestStorageValidation:setUp()
    CaptureWarnings()
end

function TestStorageValidation:tearDown()
    RestoreWarnings()
end

function TestStorageValidation:testDuplicateAliasWarns()
    AdamantModpackLib_Internal.storage.validate({
        { type = "bool", alias = "Flag", configKey = "FlagA", default = false },
        { type = "bool", alias = "Flag", configKey = "FlagB", default = false },
    }, "DuplicateAlias")

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "duplicate alias 'Flag'")
end

function TestStorageValidation:testDuplicateConfigKeyWarns()
    AdamantModpackLib_Internal.storage.validate({
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

    AdamantModpackLib_Internal.storage.validate(storage, "TransientRoot")

    lu.assertEquals(#lib.hashing.getRoots(storage), 1)
    lu.assertEquals(lib.hashing.getRoots(storage)[1].alias, "Enabled")
    lu.assertNotNil(lib.hashing.getAliases(storage).FilterText)
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

    AdamantModpackLib_Internal.storage.validate(storage, "PackedTest")

    lu.assertEquals(storage[1].default, 5)
    lu.assertNotNil(lib.hashing.getAliases(storage).EnabledBit)
    lu.assertNotNil(lib.hashing.getAliases(storage).ModeBits)
    lu.assertEquals(#Warnings, 0)
end

function TestStorageValidation:testBoolStorageRoundTripsHash()
    local node = { type = "bool", alias = "Enabled", configKey = "Enabled", default = false }
    local storage = { node }
    AdamantModpackLib_Internal.storage.validate(storage, "BoolHash")

    lu.assertEquals(lib.hashing.toHash(node, true), "1")
    lu.assertTrue(lib.hashing.fromHash(node, "1"))
    lu.assertFalse(lib.hashing.fromHash(node, "0"))
end

function TestStorageValidation:testResetSessionToDefaultsResetsChangedPersistentRoots()
    local config = { Flag = true, Count = 3, Filter = "ignored" }
    local definition = lib.prepareDefinition({}, {
        storage = {
            { type = "bool", alias = "Flag", configKey = "Flag", default = false },
            { type = "int", alias = "Count", configKey = "Count", default = 1, min = 0, max = 5 },
            { type = "string", alias = "Filter", lifetime = "transient", default = "", maxLen = 32 },
        },
    })
    local _, session = lib.createStore(config, definition)

    session.write("Filter", "live")
    local changed, count = lib.resetStorageToDefaults(definition.storage, session)

    lu.assertTrue(changed)
    lu.assertEquals(count, 2)
    lu.assertFalse(session.read("Flag"))
    lu.assertEquals(session.read("Count"), 1)
    lu.assertEquals(session.read("Filter"), "live")
end

function TestStorageValidation:testResetSessionToDefaultsCanExcludeAliases()
    local config = { Flag = true, ViewRegion = "Surface" }
    local definition = lib.prepareDefinition({}, {
        storage = {
            { type = "bool", alias = "Flag", configKey = "Flag", default = false },
            { type = "string", alias = "ViewRegion", configKey = "ViewRegion", default = "Underworld" },
        },
    })
    local _, session = lib.createStore(config, definition)

    local changed, count = lib.resetStorageToDefaults(definition.storage, session, {
        exclude = { ViewRegion = true },
    })

    lu.assertTrue(changed)
    lu.assertEquals(count, 1)
    lu.assertFalse(session.read("Flag"))
    lu.assertEquals(session.read("ViewRegion"), "Surface")
end
