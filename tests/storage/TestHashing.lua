local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestHashing = {}

function TestHashing:setUp()
    self.harness = createLibHarness()
    self.storage = self.harness.storage
end

function TestHashing:tearDown()
    self.harness = nil
    self.storage = nil
end

local function prepareStorage(storageApi)
    local storage = {
        { type = "bool", alias = "EnabledFlag", default = false },
        { type = "int", alias = "Count", default = 1, min = 0, max = 7 },
        { type = "string", alias = "Name", default = "A", maxLen = 32 },
        { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 32 },
        {
            type = "packedInt",
            alias = "Packed",
            width = 3,
            bits = {
                { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = true },
                { alias = "ModeBits", offset = 1, width = 2, type = "int", default = 2, min = 0, max = 3 },
            },
        },
    }
    storageApi.validate(storage, "HashingTest")
    return storage
end

function TestHashing:testRootsExcludeTransientNodesAndAliasesIncludePackedBits()
    local storage = prepareStorage(self.storage)
    local roots = self.storage.getRoots(storage)
    local aliases = self.storage.getAliases(storage)

    lu.assertEquals(#roots, 4)
    lu.assertEquals(roots[1].alias, "EnabledFlag")
    lu.assertEquals(roots[4].alias, "Packed")
    lu.assertNotNil(aliases.FilterText)
    lu.assertNotNil(aliases.EnabledBit)
    lu.assertNotNil(aliases.ModeBits)
end

function TestHashing:testHashCodecRoundTripsSupportedStorageTypes()
    local storage = prepareStorage(self.storage)
    local aliases = self.storage.getAliases(storage)

    lu.assertEquals(self.storage.toHash(aliases.EnabledFlag, true), "1")
    lu.assertEquals(self.storage.toHash(aliases.EnabledFlag, false), "0")
    lu.assertTrue(self.storage.fromHash(aliases.EnabledFlag, "1"))
    lu.assertFalse(self.storage.fromHash(aliases.EnabledFlag, "0"))
    lu.assertEquals(self.storage.toHash(aliases.Count, 6), "6")
    lu.assertEquals(self.storage.fromHash(aliases.Count, "99"), 7)
    lu.assertEquals(self.storage.toHash(aliases.Name, "Athena"), "Athena")
    lu.assertEquals(self.storage.fromHash(aliases.Name, "Apollo"), "Apollo")
    lu.assertEquals(self.storage.toHash({ type = "unknown" }, "x"), nil)
    lu.assertEquals(self.storage.fromHash({ type = "unknown" }, "x"), nil)
end

function TestHashing:testPackedAliasesResolveFromPreparedNode()
    local storage = prepareStorage(self.storage)
    local aliases = self.storage.getAliases(storage)
    local packedAliases = self.storage.packed.getPackedAliases(aliases.Packed)

    lu.assertEquals(#packedAliases, 2)
    lu.assertEquals(packedAliases[1].alias, "EnabledBit")
    lu.assertEquals(packedAliases[1].label, "EnabledBit")
    lu.assertEquals(packedAliases[1].node, aliases.EnabledBit)
    lu.assertEquals(packedAliases[2].alias, "ModeBits")
    lu.assertEquals(packedAliases[2].node, aliases.ModeBits)
end
