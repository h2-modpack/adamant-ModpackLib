local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestHashing = {}

function TestHashing:setUp()
    self.harness = createLibHarness()
    self.storage = self.harness.storage
    self.hashing = assert(self.harness.hashing, "hashing framework surface missing")
end

function TestHashing:tearDown()
    self.harness = nil
    self.storage = nil
    self.hashing = nil
end

local function prepareStorage(storageService)
    local storage = {
        { type = "bool", alias = "EnabledFlag", default = false },
        { type = "int", alias = "Count", default = 1, min = 0, max = 7 },
        { type = "string", alias = "Name", default = "A", maxLen = 32 },
        { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 32 },
        {
            type = "packedInt",
            alias = "Packed",
            bits = {
                { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = true },
                { alias = "ModeBits", offset = 1, width = 2, type = "int", default = 2, min = 0, max = 3 },
            },
        },
    }
    storageService.validate(storage, "HashingTest")
    return storage
end

function TestHashing:testPackWidthDerivesFromRawNodeShape()
    lu.assertEquals(self.hashing.getPackWidth({ type = "bool" }), 1)
    lu.assertEquals(self.hashing.getPackWidth({ type = "int", min = 0, max = 7 }), 3)
    lu.assertEquals(self.hashing.getPackWidth({ type = "int", min = 0, max = 15 }), 4)
    lu.assertEquals(self.hashing.getPackWidth({ type = "int", min = 1, max = 12 }), 4)
    lu.assertEquals(self.hashing.getPackWidth({ type = "int", min = 0, max = 7, width = 5 }), 5)
    lu.assertNil(self.hashing.getPackWidth({ type = "int", min = 0 }))
    lu.assertNil(self.hashing.getPackWidth({ type = "string" }))
    lu.assertNil(self.hashing.getPackWidth({ type = "unknown" }))
end

function TestHashing:testRootsExcludeTransientNodesAndAliasesIncludePackedBits()
    local storage = prepareStorage(self.storage)
    local roots = self.hashing.getRoots(storage)
    local aliases = self.hashing.getAliases(storage)

    lu.assertEquals(#roots, 4)
    lu.assertEquals(roots[1].alias, "EnabledFlag")
    lu.assertEquals(roots[4].alias, "Packed")
    lu.assertNotNil(aliases.FilterText)
    lu.assertNotNil(aliases.EnabledBit)
    lu.assertNotNil(aliases.ModeBits)
end

function TestHashing:testHashCodecRoundTripsSupportedStorageTypes()
    local storage = prepareStorage(self.storage)
    local aliases = self.hashing.getAliases(storage)

    lu.assertEquals(self.hashing.toHash(aliases.EnabledFlag, true), "1")
    lu.assertEquals(self.hashing.toHash(aliases.EnabledFlag, false), "0")
    lu.assertTrue(self.hashing.fromHash(aliases.EnabledFlag, "1"))
    lu.assertFalse(self.hashing.fromHash(aliases.EnabledFlag, "0"))
    lu.assertEquals(self.hashing.toHash(aliases.Count, 6), "6")
    lu.assertEquals(self.hashing.fromHash(aliases.Count, "99"), 7)
    lu.assertEquals(self.hashing.toHash(aliases.Name, "Athena"), "Athena")
    lu.assertEquals(self.hashing.fromHash(aliases.Name, "Apollo"), "Apollo")
    lu.assertEquals(self.hashing.toHash({ type = "unknown" }, "x"), nil)
    lu.assertEquals(self.hashing.fromHash({ type = "unknown" }, "x"), nil)
end

function TestHashing:testPackWidthAndPackedBitReadWrite()
    local storage = prepareStorage(self.storage)
    local aliases = self.hashing.getAliases(storage)

    lu.assertEquals(self.hashing.getPackWidth(aliases.EnabledFlag), 1)
    lu.assertEquals(self.hashing.getPackWidth(aliases.Count), 3)
    lu.assertEquals(self.hashing.getPackWidth(aliases.Name), nil)
    lu.assertEquals(self.hashing.getPackWidth(aliases.Packed), 3)

    local packed = 0
    packed = self.hashing.writePackedBits(packed, 0, 1, 1)
    packed = self.hashing.writePackedBits(packed, 1, 2, 3)

    lu.assertEquals(packed, 7)
    lu.assertEquals(self.hashing.readPackedBits(packed, 0, 1), 1)
    lu.assertEquals(self.hashing.readPackedBits(packed, 1, 2), 3)

    packed = self.hashing.writePackedBits(packed, 1, 2, 99)
    lu.assertEquals(self.hashing.readPackedBits(packed, 1, 2), 3)
end

function TestHashing:testPackedAliasesResolveFromPreparedNode()
    local storage = prepareStorage(self.storage)
    local aliases = self.hashing.getAliases(storage)
    local packedAliases = self.storage.packed.getPackedAliases(aliases.Packed)

    lu.assertEquals(#packedAliases, 2)
    lu.assertEquals(packedAliases[1].alias, "EnabledBit")
    lu.assertEquals(packedAliases[1].label, "EnabledBit")
    lu.assertEquals(packedAliases[1].node, aliases.EnabledBit)
    lu.assertEquals(packedAliases[2].alias, "ModeBits")
    lu.assertEquals(packedAliases[2].node, aliases.ModeBits)
end
