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
    }

    local prepared = self.h.moduleHost.prepareDefinition(owner, raw)
    raw.name = "Changed Name"
    raw.storage[1].alias = "ChangedAlias"

    lu.assertNotIs(prepared, raw)
    lu.assertEquals(prepared.name, "Example")
    lu.assertEquals(prepared.storage[1].alias, "Enabled")
    lu.assertEquals(prepared.storage[2].alias, "DebugMode")
    lu.assertEquals(prepared.storage[3].alias, "AdamantFramework_PackRestoreSnapshot")
    lu.assertEquals(prepared.storage[4].alias, "EnabledFlag")
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

function TestModuleHost_PrepareDefinition:testPrepareDefinitionAllowsLibInternalActions()
    local prepared = self.h.moduleHost.prepareDefinitionWithInternalDeclarations({}, {
        id = "InternalActionsModule",
        name = "Internal Actions Module",
        storage = {},
        actions = {
            publicAction = function() end,
        },
    }, nil, {
        actions = {
            _PrivateAction = function() end,
        },
    })

    lu.assertEquals(prepared._actionOrder, { "_PrivateAction", "publicAction" })
    lu.assertEquals(type(prepared.actions._PrivateAction), "function")
    lu.assertEquals(type(prepared.actions.publicAction), "function")
end

function TestModuleHost_PrepareDefinition:testPrepareDefinitionRejectsInvalidInternalActions()
    lu.assertErrorMsgContains("internal action key 'PrivateAction' must start with '_'", function()
        self.h.moduleHost.prepareDefinitionWithInternalDeclarations({}, {
            id = "InvalidInternalActionsModule",
            name = "Invalid Internal Actions Module",
            storage = {},
        }, nil, {
            actions = {
                PrivateAction = function() end,
            },
        })
    end)
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
    lu.assertErrorMsgContains("action key '_privateAction'", function()
        self.h.moduleHost.prepareDefinition({}, {
            id = "PrivateActionModule",
            name = "Private Action Module",
            storage = {},
            actions = {
                _privateAction = function() end,
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
    local rebuildStorageAlias = nil

    self.h.coordinator.register("test-pack", { ModEnabled = true })
    self.h.coordinator.registerRebuild("test-pack", function(reason)
        rebuildReason = reason
        local liveModule = self.h.moduleHost.getLiveModule("test-module")
        local storage = liveModule and liveModule.getStorage() or nil
        local lastStorage = storage and storage[#storage] or nil
        rebuildStorageAlias = lastStorage and lastStorage.alias or nil
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
    lu.assertNotNil(self.h.moduleHost.getLiveModule("test-module"))
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(rebuildReason.kind, "structural_definition_changed")
    lu.assertEquals(rebuildReason.moduleId, "Example")
    lu.assertEquals(rebuildReason.modpack, "test-pack")
    lu.assertEquals(rebuildStorageAlias, "OtherFlag")
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
    lu.assertStrContains(err, "managed_module.structural_rebuild_unavailable")
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
    lu.assertStrContains(err, "managed_module.structural_rebuild_unavailable")
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
