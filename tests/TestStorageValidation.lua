local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestStorageValidation = {}

local function prepareDefinition(harness, definition)
    return harness.moduleHost.prepareDefinition({}, definition)
end

local function createModuleState(harness, config, definition)
    local state = harness.moduleState.create(config, definition)
    return state.persistentState, state.stagedState
end

function TestStorageValidation:setUp()
    self.harness = createLibHarness()
    self.storage = self.harness.storage
    self.hashing = assert(self.harness.hashing, "hashing framework surface missing")
end

function TestStorageValidation:tearDown()
    self.harness = nil
    self.storage = nil
    self.hashing = nil
end

function TestStorageValidation:testDuplicateAliasFails()
    lu.assertErrorMsgContains("duplicate alias 'Flag'", function()
        self.storage.validate({
            { type = "bool", alias = "Flag", default = false },
            { type = "bool", alias = "Flag", default = false },
        }, "DuplicateAlias")
    end)
end

function TestStorageValidation:testInvalidRootAliasFails()
    lu.assertErrorMsgContains("alias 'Bad-Alias' must start with a letter", function()
        self.storage.validate({
            { type = "bool", alias = "Bad-Alias", default = false },
        }, "InvalidRootAlias")
    end)
end

function TestStorageValidation:testInternalRootAliasFailsForAuthoredStorage()
    lu.assertErrorMsgContains("alias '_PrivateFlag' must start with a letter", function()
        self.storage.validate({
            { type = "bool", alias = "_PrivateFlag", default = false },
        }, "InternalRootAlias")
    end)
end

function TestStorageValidation:testInvalidPackedChildAliasFails()
    lu.assertErrorMsgContains("alias 'Bad.Child' must start with a letter", function()
        self.storage.validate({
            {
                type = "packedInt",
                alias = "Packed",
                bits = {
                    { alias = "Bad.Child", offset = 0, width = 1, type = "bool", default = false },
                },
            },
        }, "InvalidPackedChildAlias")
    end)
end

function TestStorageValidation:testInvalidTableRowAliasFails()
    lu.assertErrorMsgContains("alias 'Bad=Row' must start with a letter", function()
        self.storage.validate({
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Bad=Row", default = false },
                },
            },
        }, "InvalidTableRowAlias")
    end)
end

function TestStorageValidation:testStringDefaultLongerThanMaxLenFails()
    lu.assertErrorMsgContains("string default length must not exceed maxLen 3", function()
        prepareDefinition(self.harness, {
            id = "StringDefaultMaxLen",
            name = "String Default MaxLen",
            storage = {
                { type = "string", alias = "Name", default = "abcd", maxLen = 3 },
            },
        })
    end)
end

function TestStorageValidation:testStringMaxLenNormalizesStorageAndHashValues()
    local definition = prepareDefinition(self.harness, {
        id = "StringMaxLen",
        name = "String MaxLen",
        storage = {
            { type = "string", alias = "Name", default = "", maxLen = 3 },
        },
    })
    local node = self.storage.getAliases(definition.storage).Name

    lu.assertEquals(self.storage.NormalizeStorageValue(node, "abcdef"), "abc")
    lu.assertEquals(self.hashing.toHash(node, "abcdef"), "abc")
    lu.assertEquals(self.hashing.fromHash(node, "abcdef"), "abc")
end

function TestStorageValidation:testStringMaxLenNormalizesTableRows()
    local definition = prepareDefinition(self.harness, {
        id = "TableStringMaxLen",
        name = "Table String MaxLen",
        storage = {
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "string", alias = "Note", default = "", maxLen = 4 },
                },
            },
        },
    })
    local _, stagedState = createModuleState(self.harness, {}, definition)
    local rows = stagedState.table("Rows")

    lu.assertTrue(rows:write(1, "Note", "abcdef"))
    lu.assertEquals(rows:read(1, "Note"), "abcd")
end

function TestStorageValidation:testTransientRootRegistersAliasButNotPersistedRoots()
    local storage = {
        { type = "bool", alias = "Enabled", default = false },
        { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
    }

    self.storage.validate(storage, "TransientRoot")

    lu.assertEquals(#self.storage.getRoots(storage), 1)
    lu.assertEquals(self.storage.getRoots(storage)[1].alias, "Enabled")
    lu.assertNotNil(self.storage.getAliases(storage).FilterText)
end

function TestStorageValidation:testPersistFalseRootRegistersStagedStateAliasButNotHashRoot()
    local storage = {
        { type = "bool", alias = "Enabled", default = false },
        { type = "bool", alias = "FilterEnabled", default = false, persist = false, hash = false },
    }

    self.storage.validate(storage, "TransientRoot")

    lu.assertEquals(#self.storage.getRoots(storage), 1)
    lu.assertEquals(self.storage.getRoots(storage)[1].alias, "Enabled")
    lu.assertNotNil(self.storage.getAliases(storage).FilterEnabled)
    lu.assertEquals(#self.storage.getStagedRoots(storage), 2)
end

function TestStorageValidation:testStageFieldFailsAsUnknownStorageField()
    lu.assertErrorMsgContains("unknown storage field 'stage'", function()
        self.storage.validate({
            {
                type = "bool",
                alias = "OldStageAxis",
                stage = false,
                hash = false,
                default = false,
            },
        }, "StageField")
    end)
end

function TestStorageValidation:testUnknownRootStorageFieldFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        self.storage.validate({
            { type = "int", alias = "Count", default = 0, min = 0, max = 10, defalt = 1 },
        }, "UnknownRootField")
    end)
end

function TestStorageValidation:testUnknownFieldForStorageTypeFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        self.storage.validate({
            { type = "bool", alias = "Flag", default = false, width = 1 },
        }, "UnknownTypeField")
    end)
end

function TestStorageValidation:testUnknownPackedBitFieldFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        self.storage.validate({
            {
                type = "packedInt",
                alias = "Packed",
                bits = {
                    { alias = "Bit", offset = 0, width = 1, type = "bool", default = false, defalt = true },
                },
            },
        }, "UnknownPackedBitField")
    end)
end

function TestStorageValidation:testUnknownTableRowFieldFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        self.storage.validate({
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "int", alias = "Count", default = 0, min = 0, max = 10, with = 4 },
                },
            },
        }, "UnknownTableRowField")
    end)
end

function TestStorageValidation:testPackedIntDerivesChildAliasesAndDefault()
    local storage = {
        {
            type = "packedInt",
            alias = "Packed",
            bits = {
                { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = true },
                { alias = "ModeBits", offset = 1, width = 2, type = "int", default = 2 },
            },
        },
    }

    self.storage.validate(storage, "PackedTest")

    lu.assertEquals(storage[1].default, 5)
    lu.assertNotNil(self.storage.getAliases(storage).EnabledBit)
    lu.assertNotNil(self.storage.getAliases(storage).ModeBits)
end
