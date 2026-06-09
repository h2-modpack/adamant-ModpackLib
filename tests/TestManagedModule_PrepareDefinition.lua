local lu = require("luaunit")
local createManagedModuleHarness = require("tests/harness/create_managed_module_harness")

TestManagedModule_PrepareDefinition = {}

function TestManagedModule_PrepareDefinition:setUp()
    self.h = createManagedModuleHarness()
    self.h:captureWarnings()
end

function TestManagedModule_PrepareDefinition:tearDown()
    self.h:restoreWarnings()
end

local function createAndActivate(h, pluginGuid, definition, store, stagedState)
    local module = h.managedModule.create({
        pluginGuid = pluginGuid,
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
    })
    return module.activate()
end

function TestManagedModule_PrepareDefinition:testPrepareDefinitionReturnsPreparedClone()
    local owner = {}
    local raw = {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    }

    local prepared = self.h.managedModule.prepareDefinition(owner, raw)
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

function TestManagedModule_PrepareDefinition:testPrepareDefinitionMarksStructuralReloadMismatch()
    local owner = {}

    self.h.managedModule.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = self.h.managedModule.prepareDefinition(owner, {
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

function TestManagedModule_PrepareDefinition:testPrepareDefinitionInjectsBuiltInStorage()
    local prepared = self.h.managedModule.prepareDefinition({}, {
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

function TestManagedModule_PrepareDefinition:testPrepareDefinitionRejectsReservedBuiltInStorageAliases()
    lu.assertErrorMsgContains("storage alias 'Enabled' is reserved by Lib", function()
        self.h.managedModule.prepareDefinition({}, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "bool", alias = "Enabled", default = true },
            },
        })
    end)
    lu.assertErrorMsgContains("storage alias 'AdamantFramework_PackRestoreSnapshot' is reserved by Lib", function()
        self.h.managedModule.prepareDefinition({}, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "int", alias = "AdamantFramework_PackRestoreSnapshot", default = 0, min = 0, max = 2 },
            },
        })
    end)
end

function TestManagedModule_PrepareDefinition:testPrepareDefinitionRejectsAuthoredInternalStorageAlias()
    lu.assertErrorMsgContains("alias '_PrivateFlag' must start with a letter", function()
        self.h.managedModule.prepareDefinition({}, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "bool", alias = "_PrivateFlag", default = false },
            },
        })
    end)
end

function TestManagedModule_PrepareDefinition:testPrepareDefinitionRejectsInvalidMetadataFieldTypes()
    lu.assertErrorMsgContains("definition.invalid_field_type", function()
        self.h.managedModule.prepareDefinition({}, {
            modpack = "test-pack",
            id = "Example",
            name = 7,
            storage = {},
        })
    end)
end

function TestManagedModule_PrepareDefinition:testPrepareDefinitionPreparesActionsInDeterministicOrder()
    local prepared = self.h.managedModule.prepareDefinition({}, {
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

function TestManagedModule_PrepareDefinition:testPrepareDefinitionAllowsLibInternalActions()
    local prepared = self.h.managedModule.prepareDefinitionWithInternalDeclarations({}, {
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

function TestManagedModule_PrepareDefinition:testPrepareDefinitionRejectsInvalidInternalActions()
    lu.assertErrorMsgContains("internal action key 'PrivateAction' must start with '_'", function()
        self.h.managedModule.prepareDefinitionWithInternalDeclarations({}, {
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

function TestManagedModule_PrepareDefinition:testPrepareDefinitionRejectsInvalidActions()
    lu.assertErrorMsgContains("action key 'Bad-Key'", function()
        self.h.managedModule.prepareDefinition({}, {
            id = "BadActionsModule",
            name = "Bad Actions Module",
            storage = {},
            actions = {
                ["Bad-Key"] = function() end,
            },
        })
    end)
    lu.assertErrorMsgContains("action key '_privateAction'", function()
        self.h.managedModule.prepareDefinition({}, {
            id = "PrivateActionModule",
            name = "Private Action Module",
            storage = {},
            actions = {
                _privateAction = function() end,
            },
        })
    end)
    lu.assertErrorMsgContains("actions.reset should be function", function()
        self.h.managedModule.prepareDefinition({}, {
            id = "BadActionHandlerModule",
            name = "Bad Action Handler Module",
            storage = {},
            actions = {
                reset = true,
            },
        })
    end)
end

function TestManagedModule_PrepareDefinition:testPrepareDefinitionRejectsDefinitionWithoutId()
    lu.assertErrorMsgContains("definition.missing_id", function()
        self.h.managedModule.prepareDefinition({}, {
            name = "Missing ID",
            storage = {},
        })
    end)
end

function TestManagedModule_PrepareDefinition:testPrepareDefinitionRejectsInvalidDefinitionId()
    lu.assertErrorMsgContains("definition.id 'Bad.Id' must start with a letter", function()
        self.h.managedModule.prepareDefinition({}, {
            id = "Bad.Id",
            name = "Bad ID",
            storage = {},
        })
    end)
end

function TestManagedModule_PrepareDefinition:testPrepareDefinitionRejectsDefinitionWithoutName()
    lu.assertErrorMsgContains("definition.missing_name", function()
        self.h.managedModule.prepareDefinition({}, {
            id = "MissingName",
            storage = {},
        })
    end)
end

function TestManagedModule_PrepareDefinition:testManagedModuleRequestsCoordinatorRebuildOnStructuralMismatch()
    local owner = {}
    local rebuildReason = nil
    local rebuildStorageAlias = nil

    self.h.coordinator.register("test-pack", "Test Pack", { ModEnabled = true })
    self.h.coordinator.registerRebuild("test-pack", function(reason)
        rebuildReason = reason
        local liveModule = self.h.managedModule.getLiveModule("test-module")
        local storage = liveModule and liveModule.getStorage() or nil
        local lastStorage = storage and storage[#storage] or nil
        rebuildStorageAlias = lastStorage and lastStorage.alias or nil
        return true
    end)

    self.h.managedModule.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = self.h.managedModule.prepareDefinition(owner, {
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
    lu.assertNotNil(self.h.managedModule.getLiveModule("test-module"))
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(rebuildReason.kind, "structural_definition_changed")
    lu.assertEquals(rebuildReason.moduleId, "Example")
    lu.assertEquals(rebuildReason.modpack, "test-pack")
    lu.assertEquals(rebuildStorageAlias, "OtherFlag")
    lu.assertEquals(#self.h.warnings, 0)
end

function TestManagedModule_PrepareDefinition:testManagedModuleErrorsWhenCoordinatedRebuildCallbackIsMissing()
    local owner = {}

    self.h.coordinator.register("test-pack", "Test Pack", { ModEnabled = true })

    self.h.managedModule.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = self.h.managedModule.prepareDefinition(owner, {
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

function TestManagedModule_PrepareDefinition:testManagedModuleErrorsAndKeepsPendingReasonWhenRebuildRequestIsRejected()
    local owner = {}

    self.h.coordinator.register("test-pack", "Test Pack", { ModEnabled = true })
    self.h.coordinator.registerRebuild("test-pack", function()
        return false
    end)

    self.h.managedModule.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = self.h.managedModule.prepareDefinition(owner, {
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

function TestManagedModule_PrepareDefinition:testPrepareDefinitionKeepsStableStructuralFingerprint()
    local owner = {}

    self.h.managedModule.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    self.h.managedModule.prepareDefinition(owner, {
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

function TestManagedModule_PrepareDefinition:testCreateStoreAcceptsPreparedDefinition()
    local owner = {}
    local definition = self.h.managedModule.prepareDefinition(owner, {
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

function TestManagedModule_PrepareDefinition:testCreateStoreRejectsRawDefinition()
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

function TestManagedModule_PrepareDefinition:testCreateStoreRejectsNonTableConfig()
    local definition = self.h.managedModule.prepareDefinition({}, {
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

function TestManagedModule_PrepareDefinition:testManagedModuleRejectsRawDefinition()
    local prepared = self.h.managedModule.prepareDefinition({}, {
        id = "RejectRawDefinition",
        name = "Reject Raw Definition",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })
    local store, stagedState = self.h:createModuleState({}, prepared)

    lu.assertErrorMsgContains("prepared definition is required", function()
        self.h.managedModule.create({
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

function TestManagedModule_PrepareDefinition:testCreateStoreRequiresStorage()
    local definition = self.h.managedModule.prepareDefinition({}, {
        id = "NoStorage",
        name = "No Storage",
    })

    local store, stagedState = self.h:createModuleState({}, definition)

    lu.assertFalse(store.read("Enabled"))
    lu.assertFalse(stagedState.read("DebugMode"))
end

function TestManagedModule_PrepareDefinition:testPrepareDefinitionUsesStorageDefaultsInFingerprint()
    local owner = {}
    local prepared = self.h.managedModule.prepareDefinition(owner, {
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

function TestManagedModule_PrepareDefinition:testPrepareDefinitionTreatsStorageDefaultChangesAsStructural()
    local owner = {}

    self.h.managedModule.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
        },
    })

    self.h.managedModule.prepareDefinition(owner, {
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

function TestManagedModule_PrepareDefinition:testPrepareDefinitionRejectsUnknownStructuralSurfaceOption()
    lu.assertErrorMsgContains("unknown option 'modpack'", function()
        self.h.managedModule.prepareDefinition({}, { Count = 1 }, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
            },
        })
    end)
end

function TestManagedModule_PrepareDefinition:testPrepareDefinitionTracksQuickContentForLowerLevelHosts()
    local owner = {}

    self.h.managedModule.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "QuickSurface",
        name = "Quick Surface",
    }, {
        hasQuickContent = false,
    })

    self.h.managedModule.prepareDefinition(owner, {
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

function TestManagedModule_PrepareDefinition:testPrepareDefinitionRejectsUnknownStructuralSurfaceOption()
    lu.assertErrorMsgContains("unknown option 'quickContent'", function()
        self.h.managedModule.prepareDefinition({}, {
            id = "UnknownSurface",
            name = "Unknown Surface",
        }, {
            hasQuickContent = true,
            quickContent = true,
        })
    end)
end

function TestManagedModule_PrepareDefinition:testPrepareDefinitionFingerprintIgnoresExternalTables()
    local owner = {}

    local first = self.h.managedModule.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
        },
    })
    local second = self.h.managedModule.prepareDefinition(owner, {
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

function TestManagedModule_PrepareDefinition:testPrepareDefinitionFingerprintTracksTooltipChanges()
    local owner = {}

    self.h.managedModule.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        tooltip = "before",
        storage = {},
    })

    self.h.managedModule.prepareDefinition(owner, {
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
