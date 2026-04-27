local lu = require('luaunit')

TestPrepareDefinition = {}

function TestPrepareDefinition:setUp()
    lib.lifecycle.registerCoordinator("test-pack", nil)
    lib.lifecycle.registerCoordinatorRebuild("test-pack", nil)
    CaptureWarnings()
end

function TestPrepareDefinition:tearDown()
    lib.lifecycle.registerCoordinator("test-pack", nil)
    lib.lifecycle.registerCoordinatorRebuild("test-pack", nil)
    RestoreWarnings()
end

function TestPrepareDefinition:testPrepareDefinitionReturnsPreparedClone()
    local owner = {}
    local raw = {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
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

    local prepared = lib.prepareDefinition(owner, raw)
    raw.name = "Changed Name"
    raw.storage[1].alias = "ChangedAlias"
    raw.hashGroupPlan[1].keyPrefix = "changed_group"

    lu.assertNotIs(prepared, raw)
    lu.assertEquals(prepared.name, "Example")
    lu.assertEquals(prepared.storage[1].alias, "EnabledFlag")
    lu.assertEquals(prepared.hashGroupPlan[1].keyPrefix, "group")
    lu.assertTrue(prepared._preparedDefinition)
    lu.assertEquals(owner.requiresFullReload, nil)
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testPrepareDefinitionMarksStructuralReloadMismatch()
    local owner = {}

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
    })

    local prepared = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", configKey = "OtherFlag", default = false },
        },
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
    lu.assertEquals(prepared.storage[1].alias, "OtherFlag")
end

function TestPrepareDefinition:testCreateModuleHostRequestsCoordinatorRebuildOnStructuralMismatch()
    local owner = {}
    local rebuildReason = nil

    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = true })
    lib.lifecycle.registerCoordinatorRebuild("test-pack", function(reason)
        rebuildReason = reason
        return true
    end)

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
    })

    local prepared = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", configKey = "OtherFlag", default = false },
        },
    })

    local store, session = lib.createStore({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    local host = lib.createModuleHost({
        moduleName = "test-module",
        definition = prepared,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(lib.getLiveModuleHost("test-module"), host)
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(rebuildReason.kind, "structural_definition_changed")
    lu.assertEquals(rebuildReason.moduleId, "Example")
    lu.assertEquals(rebuildReason.modpack, "test-pack")
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testCreateModuleHostWarnsWhenCoordinatedRebuildCallbackIsMissing()
    local owner = {}

    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = true })

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
    })

    local prepared = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", configKey = "OtherFlag", default = false },
        },
    })

    local store, session = lib.createStore({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    lib.createModuleHost({
        moduleName = "test-module",
        definition = prepared,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
    lu.assertNotNil(AdamantModpackLib_Internal.pendingCoordinatorRebuilds[prepared])
end

function TestPrepareDefinition:testCreateModuleHostKeepsPendingReasonWhenRebuildRequestIsRejected()
    local owner = {}

    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = true })
    lib.lifecycle.registerCoordinatorRebuild("test-pack", function()
        return false
    end)

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
    })

    local prepared = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", configKey = "OtherFlag", default = false },
        },
    })

    local store, session = lib.createStore({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    lib.createModuleHost({
        moduleName = "test-module",
        definition = prepared,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertNotNil(AdamantModpackLib_Internal.pendingCoordinatorRebuilds[prepared])
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
end

function TestPrepareDefinition:testPrepareDefinitionIgnoresBehaviorOnlyChanges()
    local owner = {}

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        affectsRunData = true,
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        patchPlan = function() end,
    })

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        affectsRunData = true,
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        patchPlan = function()
            return "changed"
        end,
    })

    lu.assertEquals(owner.requiresFullReload, nil)
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testCreateStoreAcceptsPreparedDefinition()
    local owner = {}
    local definition = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
    })

    local store, session = lib.createStore({
        EnabledFlag = true,
    }, definition)

    lu.assertEquals(store.read("EnabledFlag"), true)
    lu.assertEquals(session.read("EnabledFlag"), true)
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testCreateStoreRejectsRawDefinition()
    lu.assertErrorMsgContains(
        "createStore expects a prepared definition",
        function()
            lib.createStore({}, {
                storage = {
                    { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
                },
            })
        end)
end

function TestPrepareDefinition:testPrepareDefinitionPreservesHashGroupPlan()
    local owner = {}
    local prepared = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
            { type = "int", alias = "Tier", configKey = "Tier", default = 0, min = 0, max = 3 },
            { type = "bool", alias = "DebugFlag", configKey = "DebugFlag", default = false },
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
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testPrepareDefinitionHydratesMissingDefaultsBeforeFingerprint()
    local owner = {}
    local prepared = lib.prepareDefinition(owner, {
        EnabledFlag = true,
        Count = 7,
    }, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag" },
            { type = "int", alias = "Count", configKey = "Count", min = 0, max = 10 },
        },
    })

    lu.assertTrue(prepared.storage[1].default)
    lu.assertEquals(prepared.storage[2].default, 7)
    lu.assertStrContains(prepared._structuralFingerprint, "EnabledFlag")
    lu.assertStrContains(prepared._structuralFingerprint, "Count")
end

function TestPrepareDefinition:testPrepareDefinitionTreatsDefaultHydrationChangesAsStructural()
    local owner = {}

    lib.prepareDefinition(owner, {
        Count = 3,
    }, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", configKey = "Count", min = 0, max = 10 },
        },
    })

    lib.prepareDefinition(owner, {
        Count = 4,
    }, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", configKey = "Count", min = 0, max = 10 },
        },
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
end

function TestPrepareDefinition:testPrepareDefinitionFingerprintTracksHashGroupPlanChanges()
    local owner = {}

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "LargeA", configKey = "LargeA", default = 0, min = 0, max = 65535 },
            { type = "int", alias = "LargeB", configKey = "LargeB", default = 0, min = 0, max = 65535 },
            { type = "bool", alias = "Flag", configKey = "Flag", default = false },
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

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "LargeA", configKey = "LargeA", default = 0, min = 0, max = 65535 },
            { type = "int", alias = "LargeB", configKey = "LargeB", default = 0, min = 0, max = 65535 },
            { type = "bool", alias = "Flag", configKey = "Flag", default = false },
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
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
end
