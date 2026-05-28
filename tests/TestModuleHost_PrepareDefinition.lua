local lu = require("luaunit")
local createModuleHostHarness = require("tests/harness/create_module_host_harness")

TestModuleHost_PrepareDefinition = {}

function TestModuleHost_PrepareDefinition:setUp()
    self.h = createModuleHostHarness()
    self.h:captureWarnings()
end

function TestModuleHost_PrepareDefinition:tearDown()
    self.h:restoreWarnings()
end

local function createAndActivate(h, pluginGuid, definition, store, stagedState)
    local module = h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
    })
    return module.activate()
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionReturnsPreparedClone()
    local owner = {}
    local raw = {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
        hashGroupPlan = {
            {
                keyPrefix = "group",
                items = {
                    "EnabledFlag",
                },
            },
        },
    }

    local prepared = self.h.moduleHost.prepareDefinition(owner, raw)
    raw.name = "Changed Name"
    raw.storage[1].alias = "ChangedAlias"
    raw.hashGroupPlan[1].keyPrefix = "changed_group"

    lu.assertNotIs(prepared, raw)
    lu.assertEquals(prepared.name, "Example")
    lu.assertEquals(prepared.storage[1].alias, "Enabled")
    lu.assertEquals(prepared.storage[2].alias, "DebugMode")
    lu.assertEquals(prepared.storage[3].alias, "AdamantFramework_PackRestoreSnapshot")
    lu.assertEquals(prepared.storage[4].alias, "EnabledFlag")
    lu.assertEquals(prepared.hashGroupPlan[1].keyPrefix, "group")
    lu.assertTrue(prepared._preparedDefinition)
    lu.assertEquals(owner.requiresFullReload, nil)
    lu.assertEquals(#self.h.warnings, 0)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionMarksStructuralReloadMismatch()
    local owner = {}

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "structural definition changed during hot reload")
    lu.assertEquals(prepared.storage[4].alias, "OtherFlag")
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionInjectsBuiltInStorage()
    local prepared = self.h.moduleHost.prepareDefinition({}, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 0, min = 0, max = 10 },
        },
    })

    lu.assertEquals(prepared.storage[1].alias, "Enabled")
    lu.assertFalse(prepared.storage[1].default)
    lu.assertEquals(prepared.storage[2].alias, "DebugMode")
    lu.assertFalse(prepared.storage[2].default)
    lu.assertFalse(prepared.storage[2].hash)
    lu.assertEquals(prepared.storage[3].alias, "AdamantFramework_PackRestoreSnapshot")
    lu.assertEquals(prepared.storage[3].default, 0)
    lu.assertEquals(prepared.storage[3].min, 0)
    lu.assertEquals(prepared.storage[3].max, 2)
    lu.assertFalse(prepared.storage[3].hash)
    lu.assertEquals(prepared.storage[4].alias, "Count")
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsReservedBuiltInStorageAliases()
    lu.assertErrorMsgContains("storage alias 'Enabled' is reserved by Lib", function()
        self.h.moduleHost.prepareDefinition({}, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "bool", alias = "Enabled", default = true },
            },
        })
    end)
    lu.assertErrorMsgContains("storage alias 'AdamantFramework_PackRestoreSnapshot' is reserved by Lib", function()
        self.h.moduleHost.prepareDefinition({}, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "int", alias = "AdamantFramework_PackRestoreSnapshot", default = 0, min = 0, max = 2 },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsAuthoredInternalStorageAlias()
    lu.assertErrorMsgContains("alias '_PrivateFlag' must start with a letter", function()
        self.h.moduleHost.prepareDefinition({}, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "bool", alias = "_PrivateFlag", default = false },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsInvalidMetadataFieldTypes()
    lu.assertErrorMsgContains("definition.invalid_field_type", function()
        self.h.moduleHost.prepareDefinition({}, {
            modpack = "test-pack",
            id = "Example",
            name = 7,
            storage = {},
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionPreparesActionsInDeterministicOrder()
    local prepared = self.h.moduleHost.prepareDefinition({}, {
        id = "ActionsModule",
        name = "Actions Module",
        storage = {},
        actions = {
            second = function() end,
            first = function() end,
        },
    })

    lu.assertEquals(prepared._actionOrder, { "first", "second" })
    lu.assertEquals(type(prepared.actions.first), "function")
    lu.assertEquals(type(prepared.actions.second), "function")
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsInvalidActions()
    lu.assertErrorMsgContains("action key 'Bad-Key'", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadActionsModule",
            name = "Bad Actions Module",
            storage = {},
            actions = {
                ["Bad-Key"] = function() end,
            },
        })
    end)
    lu.assertErrorMsgContains("actions.reset should be function", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadActionHandlerModule",
            name = "Bad Action Handler Module",
            storage = {},
            actions = {
                reset = true,
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsDefinitionWithoutId()
    lu.assertErrorMsgContains("definition.missing_id", function()
        self.h.moduleHost.prepareDefinition({}, {
            name = "Missing ID",
            storage = {},
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsInvalidDefinitionId()
    lu.assertErrorMsgContains("definition.id 'Bad.Id' must start with a letter", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "Bad.Id",
            name = "Bad ID",
            storage = {},
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsDefinitionWithoutName()
    lu.assertErrorMsgContains("definition.missing_name", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "MissingName",
            storage = {},
        })
    end)
end

function TestModuleHost_PrepareDefinition:testCreateModuleHostRequestsCoordinatorRebuildOnStructuralMismatch()
    local owner = {}
    local rebuildReason = nil

    self.h.coordinator.register("test-pack", { ModEnabled = true })
    self.h.coordinator.registerRebuild("test-pack", function(reason)
        rebuildReason = reason
        return true
    end)

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })

    local store, stagedState = self.h:createModuleState({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    createAndActivate(self.h, "test-module", prepared, store, stagedState)

    lu.assertTrue(owner.requiresFullReload)
    lu.assertNotNil(self.h.moduleHost.getLiveHost("test-module"))
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(rebuildReason.kind, "structural_definition_changed")
    lu.assertEquals(rebuildReason.moduleId, "Example")
    lu.assertEquals(rebuildReason.modpack, "test-pack")
    lu.assertEquals(#self.h.warnings, 0)
end

function TestModuleHost_PrepareDefinition:testCreateModuleHostErrorsWhenCoordinatedRebuildCallbackIsMissing()
    local owner = {}

    self.h.coordinator.register("test-pack", { ModEnabled = true })

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })

    local store, stagedState = self.h:createModuleState({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    local ok, err = createAndActivate(self.h, "test-module", prepared, store, stagedState)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "host.structural_rebuild_unavailable")
    lu.assertTrue(owner.requiresFullReload)
    lu.assertNotNil(self.h.moduleRegistry.getPendingCoordinatorRebuild(prepared))
end

function TestModuleHost_PrepareDefinition:testCreateModuleHostErrorsAndKeepsPendingReasonWhenRebuildRequestIsRejected()
    local owner = {}

    self.h.coordinator.register("test-pack", { ModEnabled = true })
    self.h.coordinator.registerRebuild("test-pack", function()
        return false
    end)

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })

    local store, stagedState = self.h:createModuleState({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    local ok, err = createAndActivate(self.h, "test-module", prepared, store, stagedState)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "host.structural_rebuild_unavailable")
    lu.assertTrue(owner.requiresFullReload)
    lu.assertNotNil(self.h.moduleRegistry.getPendingCoordinatorRebuild(prepared))
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionKeepsStableStructuralFingerprint()
    local owner = {}

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    lu.assertEquals(owner.requiresFullReload, nil)
    lu.assertEquals(#self.h.warnings, 0)
end

function TestModuleHost_PrepareDefinition:testCreateStoreAcceptsPreparedDefinition()
    local owner = {}
    local definition = self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local store, stagedState = self.h:createModuleState({
        EnabledFlag = true,
    }, definition)

    lu.assertEquals(store.read("EnabledFlag"), true)
    lu.assertEquals(stagedState.read("EnabledFlag"), true)
    lu.assertEquals(#self.h.warnings, 0)
end

function TestModuleHost_PrepareDefinition:testCreateStoreRejectsRawDefinition()
    lu.assertErrorMsgContains(
        "createModuleState expects a prepared definition",
        function()
            self.h:createModuleState({}, {
                storage = {
                    { type = "bool", alias = "EnabledFlag", default = false },
                },
            })
        end)
end

function TestModuleHost_PrepareDefinition:testCreateStoreRejectsNonTableConfig()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "RejectNonTableConfig",
        name = "Reject Non Table Config",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    lu.assertErrorMsgContains("store.invalid_config", function()
        self.h:createModuleState(nil, definition)
    end)
end

function TestModuleHost_PrepareDefinition:testCreateModuleHostRejectsRawDefinition()
    local prepared = self.h.moduleHost.prepareDefinition({}, {
        id = "RejectRawDefinition",
        name = "Reject Raw Definition",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })
    local store, stagedState = self.h:createModuleState({}, prepared)

    lu.assertErrorMsgContains("prepared definition is required", function()
        self.h.moduleHost.create({
            pluginGuid = "test-raw-host",
            definition = {
                storage = {
                    { type = "bool", alias = "EnabledFlag", default = false },
                },
            },
            persistentState = store,
            stagedState = stagedState,
            drawTab = function() end,
        })
    end)
end

function TestModuleHost_PrepareDefinition:testCreateStoreRequiresStorage()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "NoStorage",
        name = "No Storage",
    })

    local store, stagedState = self.h:createModuleState({}, definition)

    lu.assertFalse(store.read("Enabled"))
    lu.assertFalse(stagedState.read("DebugMode"))
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionPreservesHashGroupPlan()
    local owner = {}
    local prepared = self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "int", alias = "Tier", default = 0, min = 0, max = 3 },
            { type = "bool", alias = "DebugFlag", default = false },
        },
        hashGroupPlan = {
            {
                keyPrefix = "main",
                items = {
                    { "EnabledFlag", "Tier" },
                    "DebugFlag",
                },
            },
        },
    })

    lu.assertEquals(prepared.hashGroupPlan[1].keyPrefix, "main")
    lu.assertEquals(prepared.hashGroupPlan[1].items[1][1], "EnabledFlag")
    lu.assertEquals(prepared.hashGroupPlan[1].items[1][2], "Tier")
    lu.assertEquals(prepared.hashGroupPlan[1].items[2], "DebugFlag")
    lu.assertEquals(#self.h.warnings, 0)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsInvalidHashGroupPrefix()
    lu.assertErrorMsgContains("hashGroupPlan[1].keyPrefix 'bad-prefix' must start with a letter", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "bad-prefix",
                    items = {
                        "EnabledFlag",
                    },
                },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsUnknownHashGroupField()
    lu.assertErrorMsgContains("unknown hashGroupPlan[1] field 'itemz'", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    itemz = {
                        "EnabledFlag",
                    },
                },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsDuplicateHashGroupPrefix()
    lu.assertErrorMsgContains("duplicate hashGroupPlan keyPrefix 'main'", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
                { type = "bool", alias = "OtherFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "EnabledFlag",
                    },
                },
                {
                    keyPrefix = "main",
                    items = {
                        "OtherFlag",
                    },
                },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsDuplicateHashGroupAlias()
    lu.assertErrorMsgContains("duplicate hashGroupPlan alias 'EnabledFlag'", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
                { type = "bool", alias = "OtherFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        { "EnabledFlag", "OtherFlag" },
                    },
                },
                {
                    keyPrefix = "extra",
                    items = {
                        "EnabledFlag",
                    },
                },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsInvalidHashGroupItemShape()
    lu.assertErrorMsgContains("hashGroupPlan[1].items[1] must be an alias string or alias list", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        7,
                    },
                },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsUnknownHashGroupAlias()
    lu.assertErrorMsgContains("references unknown storage alias 'MissingAlias'", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "MissingAlias",
                    },
                },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsHashGroupEnabledAlias()
    lu.assertErrorMsgContains("alias 'Enabled' is encoded as module enable state", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "Enabled",
                    },
                },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsHashGroupPackedChildAlias()
    lu.assertErrorMsgContains("is a packed child alias; only root storage aliases are supported", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                {
                    type = "packedInt",
                    alias = "PackedRoot",
                    bits = {
                        { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = false },
                    },
                },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "EnabledBit",
                    },
                },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsHashGroupNonHashAlias()
    lu.assertErrorMsgContains("is excluded from hashes; only hash root aliases are supported", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "string", alias = "FilterMode", persist = false, hash = false, default = "all", maxLen = 16 },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "FilterMode",
                    },
                },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsHashGroupUnpackableAlias()
    lu.assertErrorMsgContains("alias 'FilterMode' cannot be packed", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "string", alias = "FilterMode", default = "all", maxLen = 16 },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "FilterMode",
                    },
                },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsHashGroupItemOver32Bits()
    lu.assertErrorMsgContains("hashGroupPlan[1].items[1] exceeds 32 packed bits", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "int", alias = "WideA", default = 0, min = 0, max = 1, width = 20 },
                { type = "int", alias = "WideB", default = 0, min = 0, max = 1, width = 20 },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        { "WideA", "WideB" },
                    },
                },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionUsesStorageDefaultsInFingerprint()
    local owner = {}
    local prepared = self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = true },
            { type = "int", alias = "Count", default = 7, min = 0, max = 10 },
        },
    })

    lu.assertFalse(prepared.storage[1].default)
    lu.assertFalse(prepared.storage[2].default)
    lu.assertTrue(prepared.storage[4].default)
    lu.assertEquals(prepared.storage[5].default, 7)
    lu.assertStrContains(prepared._structuralFingerprint, "EnabledFlag")
    lu.assertStrContains(prepared._structuralFingerprint, "Count")
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionTreatsStorageDefaultChangesAsStructural()
    local owner = {}

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
        },
    })

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 4, min = 0, max = 10 },
        },
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "structural definition changed during hot reload")
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsLegacyDataDefaultsArgument()
    lu.assertErrorMsgContains("storage defaults on definition.storage nodes", function()
        self.h.moduleHost.prepareDefinition({}, { Count = 1 }, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
            },
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionTracksQuickContentForLowerLevelHosts()
    local owner = {}

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "QuickSurface",
        name = "Quick Surface",
    }, {
        hasQuickContent = false,
    })

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "QuickSurface",
        name = "Quick Surface",
    }, {
        hasQuickContent = true,
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "structural definition changed during hot reload")
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsUnknownStructuralSurfaceOption()
    lu.assertErrorMsgContains("unknown option 'quickContent'", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "UnknownSurface",
            name = "Unknown Surface",
        }, {
            hasQuickContent = true,
            quickContent = true,
        })
    end)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionFingerprintIgnoresExternalTables()
    local owner = {}

    local first = self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
        },
    })
    local second = self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
        },
    })

    lu.assertEquals(first._structuralFingerprint, second._structuralFingerprint)
    lu.assertNil(owner.requiresFullReload)
    lu.assertEquals(#self.h.warnings, 0)
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionFingerprintTracksHashGroupPlanChanges()
    local owner = {}

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "LargeA", default = 0, min = 0, max = 65535 },
            { type = "int", alias = "LargeB", default = 0, min = 0, max = 65535 },
            { type = "bool", alias = "Flag", default = false },
        },
        hashGroupPlan = {
            {
                keyPrefix = "split",
                items = {
                    { "LargeA", "LargeB" },
                    "Flag",
                },
            },
        },
    })

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "LargeA", default = 0, min = 0, max = 65535 },
            { type = "int", alias = "LargeB", default = 0, min = 0, max = 65535 },
            { type = "bool", alias = "Flag", default = false },
        },
        hashGroupPlan = {
            {
                keyPrefix = "split",
                items = {
                    { "LargeA" },
                    { "LargeB", "Flag" },
                },
            },
        },
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "structural definition changed during hot reload")
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionFingerprintTracksTooltipChanges()
    local owner = {}

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        tooltip = "old",
        storage = {},
    })

    self.h.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        tooltip = "new",
        storage = {},
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "structural definition changed during hot reload")
end
