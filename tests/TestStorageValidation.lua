local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestStorageValidation = {}

local function prepareDefinition(harness, definition)
    return harness.managedModule.prepareDefinition({}, definition)
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

function TestStorageValidation:testLibInternalStorageAllowsPrivateAliases()
    local definition = self.harness.moduleDefinition.prepareDefinitionWithInternalStorage({}, {
        id = "InternalStorage",
        name = "Internal Storage",
        storage = {
            { type = "bool", alias = "PublicFlag", default = false },
        },
    }, nil, {
        { type = "bool", alias = "_PrivateFlag", default = true, hash = false },
        {
            type = "packedInt",
            alias = "_PrivatePacked",
            width = 1,
            hash = false,
            bits = {
                { alias = "_PrivateBit", offset = 0, width = 1, type = "bool", default = true },
            },
        },
    })

    local aliases = self.storage.getAliases(definition.storage)
    lu.assertNotNil(aliases.PublicFlag)
    lu.assertNotNil(aliases._PrivateFlag)
    lu.assertNotNil(aliases._PrivatePacked)
    lu.assertNotNil(aliases._PrivateBit)
end

function TestStorageValidation:testLibInternalStorageUsesHyphenSeparatedPrivateAliases()
    local definition = self.harness.moduleDefinition.prepareDefinitionWithInternalStorage({}, {
        id = "InternalStorageDelimiter",
        name = "Internal Storage Delimiter",
        storage = {},
    }, nil, {
        { type = "bool", alias = "_Private-Flag", default = true, hash = false },
    })

    local aliases = self.storage.getAliases(definition.storage)
    lu.assertNotNil(aliases["_Private-Flag"])
end

function TestStorageValidation:testLibInternalStorageRejectsColonSeparatedPrivateAliases()
    lu.assertErrorMsgContains("internal alias '_Private:Flag' must start with '_'", function()
        self.harness.moduleDefinition.prepareDefinitionWithInternalStorage({}, {
            id = "InternalStorageColonDelimiter",
            name = "Internal Storage Colon Delimiter",
            storage = {},
        }, nil, {
            { type = "bool", alias = "_Private:Flag", default = true, hash = false },
        })
    end)
end

function TestStorageValidation:testLibInternalStorageRequiresPrivateAliases()
    lu.assertErrorMsgContains("internal alias 'PrivateFlag' must start with '_'", function()
        self.harness.moduleDefinition.prepareDefinitionWithInternalStorage({}, {
            id = "InternalStorage",
            name = "Internal Storage",
            storage = {},
        }, nil, {
            { type = "bool", alias = "PrivateFlag", default = true, hash = false },
        })
    end)
end

function TestStorageValidation:testLibInternalStorageDoesNotRelaxPublicRowAliases()
    lu.assertErrorMsgContains("alias '_PrivateFlag' must start with a letter", function()
        self.harness.moduleDefinition.prepareDefinitionWithInternalStorage({}, {
            id = "InternalStoragePublicRow",
            name = "Internal Storage Public Row",
            storage = {
                {
                    type = "table",
                    alias = "Rows",
                    defaultRows = 1,
                    row = {
                        { type = "bool", alias = "_PrivateFlag", default = false },
                    },
                },
            },
        }, nil, {
            { type = "bool", alias = "_PrivateFlag", default = true, hash = false },
        })
    end)
end

function TestStorageValidation:testPublicStorageCannotReachLibInternalAliases()
    local definition = self.harness.moduleDefinition.prepareDefinitionWithInternalStorage({}, {
        id = "InternalStorageAccess",
        name = "Internal Storage Access",
        storage = {
            { type = "bool", alias = "PublicFlag", default = false },
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Enabled", default = false },
                },
            },
        },
    }, nil, {
        { type = "bool", alias = "_PrivateFlag", default = true, hash = false },
        { type = "int", alias = "_PrivateRuntime", mode = "runtime", default = 0, min = 0, max = 10 },
    })
    local state = self.harness.moduleState.create({}, definition)
    local store = self.harness.moduleState.createStore(state.persistentState)
    local status = self.harness.moduleState.createRuntimeStatus(state.persistentState)
    local uiState = self.harness.moduleState.uiState.create(state.stagedState)

    lu.assertErrorMsgContains("storage.private_alias", function()
        store.get("_PrivateFlag")
    end)
    lu.assertErrorMsgContains("storage.private_alias", function()
        store.read("_PrivateFlag")
    end)
    lu.assertErrorMsgContains("storage.private_alias", function()
        status.read("_PrivateRuntime")
    end)
    lu.assertErrorMsgContains("storage.private_alias", function()
        status.write("_PrivateRuntime", 1)
    end)
    lu.assertErrorMsgContains("storage.private_alias", function()
        status.reset("_PrivateRuntime")
    end)
    lu.assertErrorMsgContains("storage.private_alias", function()
        uiState.get("_PrivateFlag")
    end)
    lu.assertErrorMsgContains("storage.private_alias", function()
        uiState.read("_PrivateFlag")
    end)
    lu.assertErrorMsgContains("storage.private_alias", function()
        uiState.write("_PrivateFlag", false)
    end)

    local publicFlag = uiState.get("PublicFlag")
    lu.assertErrorMsgContains("storage.private_alias", function()
        publicFlag:readAlias("_PrivateFlag")
    end)
    lu.assertErrorMsgContains("storage.private_alias", function()
        publicFlag:writeAlias("_PrivateFlag", false)
    end)
end

function TestStorageValidation:testInvalidPackedChildAliasFails()
    lu.assertErrorMsgContains("alias 'Bad.Child' must start with a letter", function()
        self.storage.validate({
            {
                type = "packedInt",
                alias = "Packed",
                width = 1,
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

function TestStorageValidation:testRuntimeModeDefaultsToNonHashedStorage()
    local storage = {
        { type = "bool", alias = "RuntimeFlag", mode = "runtime", default = false },
    }

    self.storage.validate(storage, "RuntimeRoot")

    local node = self.storage.getAliases(storage).RuntimeFlag
    lu.assertEquals(node._mode, "runtime")
    lu.assertTrue(node._persist)
    lu.assertFalse(node._hash)
    lu.assertEquals(#self.storage.getRoots(storage), 0)
    lu.assertEquals(#self.storage.getPersistRoots(storage), 1)
    lu.assertEquals(#self.storage.getStagedRoots(storage), 1)
end

function TestStorageValidation:testRuntimeModeIsInheritedByPackedChildren()
    local storage = {
        {
            type = "packedInt",
            alias = "RuntimePacked",
            width = 1,
            mode = "runtime",
            bits = {
                { alias = "RuntimeBit", offset = 0, width = 1, type = "bool", default = false },
            },
        },
    }

    self.storage.validate(storage, "RuntimePacked")

    local aliases = self.storage.getAliases(storage)
    lu.assertEquals(aliases.RuntimePacked._mode, "runtime")
    lu.assertEquals(aliases.RuntimeBit._mode, "runtime")
    lu.assertFalse(aliases.RuntimeBit._hash)
end

function TestStorageValidation:testRuntimeModeRejectsHashTrue()
    lu.assertErrorMsgContains("mode='runtime' requires hash=false", function()
        self.storage.validate({
            { type = "bool", alias = "RuntimeFlag", mode = "runtime", hash = true, default = false },
        }, "RuntimeHash")
    end)
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
                width = 1,
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

function TestStorageValidation:testTableRowCannotDeclareMode()
    lu.assertErrorMsgContains("row storage cannot declare mode", function()
        self.storage.validate({
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Enabled", mode = "runtime", default = false },
                },
            },
        }, "TableRowMode")
    end)
end

function TestStorageValidation:testPackedIntDerivesChildAliasesAndDefault()
    local storage = {
        {
            type = "packedInt",
            alias = "Packed",
            width = 3,
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

function TestStorageValidation:testPackedIntRequiresExplicitWidth()
    lu.assertErrorMsgContains("packedInt width is required", function()
        self.storage.validate({
            {
                type = "packedInt",
                alias = "Packed",
                bits = {
                    { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = true },
                },
            },
        }, "PackedWidth")
    end)
end

function TestStorageValidation:testPackedIntRejectsBitsOutsideDeclaredWidth()
    lu.assertErrorMsgContains("offset + width must stay within packedInt width 1", function()
        self.storage.validate({
            {
                type = "packedInt",
                alias = "Packed",
                width = 1,
                bits = {
                    { alias = "ModeBits", offset = 0, width = 2, type = "int", default = 0 },
                },
            },
        }, "PackedWidth")
    end)
end

function TestStorageValidation:testStandaloneIntRejectsWidthField()
    lu.assertErrorMsgContains("unknown storage field 'width'", function()
        self.storage.validate({
            { type = "int", alias = "Count", default = 0, width = 4 },
        }, "StandaloneInt")
    end)
end
