local lu = require('luaunit')

local function makeScalarDefinition()
    return {
        storage = {
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
            { type = "int", alias = "MaxGods", configKey = "MaxGodsPerRun", default = 3, min = 1, max = 9 },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
            { type = "stepper", binds = { value = "MaxGods" }, label = "Max Gods", min = 1, max = 9, step = 1 },
        },
    }
end

local function makePackedDefinition()
    return {
        storage = {
            {
                type = "packedInt",
                alias = "Packed",
                configKey = "Packed",
                bits = {
                    { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = false },
                    { alias = "ModeBits", offset = 1, width = 2, type = "int", default = 0 },
                },
            },
        },
        ui = {
            { type = "checkbox", binds = { value = "EnabledBit" }, label = "Enabled" },
            { type = "dropdown", binds = { value = "ModeBits" }, label = "Mode", values = { 0, 1, 2, 3 } },
        },
    }
end

local function makeTransientDefinition()
    return {
        storage = {
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
            { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 },
            { type = "string", alias = "FilterMode", lifetime = "transient", default = "all", maxLen = 16 },
            { type = "string", alias = "SummaryText", lifetime = "transient", default = "", maxLen = 128 },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
            { type = "text", text = "Filter" },
        },
    }
end

TestStore = {}

function TestStore:testCreateStoreReadsAndWritesScalarAliasesAndRawKeys()
    local config = { Enabled = false, MaxGodsPerRun = 4 }
    local store = lib.store.create(config, makeScalarDefinition())

    lu.assertFalse(store.read("Enabled"))
    lu.assertEquals(store.read("MaxGods"), 4)
    lu.assertEquals(store.read("MaxGodsPerRun"), 4)

    store.write("Enabled", true)
    store.write("MaxGods", 12)

    lu.assertTrue(config.Enabled)
    lu.assertEquals(config.MaxGodsPerRun, 9)
    lu.assertEquals(store.read("MaxGods"), 9)
end

function TestStore:testPackedAliasReadWriteUpdatesOwningRoot()
    local config = { Packed = 0 }
    local store = lib.store.create(config, makePackedDefinition())

    lu.assertFalse(store.read("EnabledBit"))
    lu.assertEquals(store.read("ModeBits"), 0)
    lu.assertEquals(store.read("Packed"), 0)

    store.write("EnabledBit", true)
    lu.assertEquals(config.Packed, 1)
    lu.assertTrue(store.read("EnabledBit"))

    store.write("ModeBits", 3)
    lu.assertEquals(config.Packed, 7)
    lu.assertEquals(store.read("ModeBits"), 3)
end

function TestStore:testReadBitsAndWriteBitsAreRawNumeric()
    local config = { Packed = 0 }
    local store = lib.store.create(config, {
        storage = {
            { type = "int", alias = "PackedValue", configKey = "Packed", default = 0 },
        },
    })

    store.writeBits("Packed", 4, 2, 9)

    lu.assertEquals(config.Packed, 48)
    lu.assertEquals(store.readBits("Packed", 4, 2), 3)
end

function TestStore:testTransientAliasesAreNotReadableThroughStore()
    CaptureWarnings()
    local config = { Enabled = false }
    local store = lib.store.create(config, makeTransientDefinition())

    lu.assertNil(store.read("FilterText"))
    store.write("FilterText", "Aphrodite")

    lu.assertEquals(store.uiState.view.FilterText, "")

    local sawReadWarning = false
    local sawWriteWarning = false
    for _, warning in ipairs(Warnings) do
        if string.find(warning, "store.read: alias 'FilterText' is transient", 1, true) then
            sawReadWarning = true
        end
        if string.find(warning, "store.write: alias 'FilterText' is transient", 1, true) then
            sawWriteWarning = true
        end
    end
    RestoreWarnings()

    lu.assertTrue(sawReadWarning)
    lu.assertTrue(sawWriteWarning)
end

TestUiState = {}

function TestUiState:testUiStateStagesScalarAliases()
    local config = { Enabled = true, MaxGodsPerRun = 5 }
    local store = lib.store.create(config, makeScalarDefinition())
    local uiState = store.uiState

    lu.assertTrue(uiState.view.Enabled)
    lu.assertEquals(uiState.view.MaxGods, 5)
    lu.assertFalse(uiState.isDirty())

    uiState.set("Enabled", false)
    lu.assertTrue(uiState.isDirty())
    lu.assertFalse(uiState.view.Enabled)

    uiState.flushToConfig()
    lu.assertFalse(uiState.isDirty())
    lu.assertFalse(config.Enabled)
end

function TestUiState:testPackedAliasEditReencodesPackedRootOnFlush()
    local config = { Packed = 0 }
    local store = lib.store.create(config, makePackedDefinition())
    local uiState = store.uiState

    uiState.set("ModeBits", 2)

    lu.assertTrue(uiState.isDirty())
    lu.assertEquals(uiState.view.ModeBits, 2)
    lu.assertEquals(uiState.view.Packed, 4)
    lu.assertEquals(config.Packed, 0)

    uiState.flushToConfig()

    lu.assertEquals(config.Packed, 4)
    lu.assertFalse(uiState.isDirty())
end

function TestUiState:testReloadFromConfigRebuildsPackedChildren()
    local config = { Packed = 0 }
    local store = lib.store.create(config, makePackedDefinition())
    local uiState = store.uiState

    config.Packed = 5
    uiState.reloadFromConfig()

    lu.assertEquals(uiState.view.Packed, 5)
    lu.assertTrue(uiState.view.EnabledBit)
    lu.assertEquals(uiState.view.ModeBits, 2)
end

function TestUiState:testAuditAndResyncUiStateDetectsPackedDrift()
    local config = { Packed = 0 }
    local store = lib.store.create(config, makePackedDefinition())
    local uiState = store.uiState

    config.Packed = 5
    local mismatches = lib.host.auditAndResyncState("PackedUiState", uiState)

    table.sort(mismatches)
    lu.assertEquals(mismatches, { "EnabledBit", "ModeBits", "Packed" })
    lu.assertTrue(uiState.view.EnabledBit)
    lu.assertEquals(uiState.view.ModeBits, 2)
    lu.assertEquals(uiState.view.Packed, 5)
end

function TestUiState:testReadonlyViewRejectsWrites()
    local config = { Enabled = true, MaxGodsPerRun = 5 }
    local store = lib.store.create(config, makeScalarDefinition())

    local ok, err = pcall(function()
        store.uiState.view.Enabled = false
    end)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "read-only")
end

function TestUiState:testTransientAliasesLiveOnlyInUiState()
    local config = { Enabled = false }
    local store = lib.store.create(config, makeTransientDefinition())
    local uiState = store.uiState

    lu.assertEquals(uiState.view.FilterText, "")
    lu.assertEquals(uiState.view.FilterMode, "all")
    lu.assertFalse(uiState.isDirty())

    uiState.set("FilterText", "Poseidon")
    uiState.set("FilterMode", "allowed")

    lu.assertEquals(uiState.view.FilterText, "Poseidon")
    lu.assertEquals(uiState.view.FilterMode, "allowed")
    lu.assertFalse(uiState.isDirty())

    uiState.flushToConfig()
    lu.assertFalse(uiState.isDirty())
    lu.assertNil(config.FilterText)
end

function TestUiState:testReloadFromConfigResetsTransientAliasesToDefaults()
    local config = { Enabled = true }
    local store = lib.store.create(config, makeTransientDefinition())
    local uiState = store.uiState

    uiState.set("FilterText", "Hera")
    uiState.set("FilterMode", "banned")
    config.Enabled = false

    uiState.reloadFromConfig()

    lu.assertFalse(uiState.view.Enabled)
    lu.assertEquals(uiState.view.FilterText, "")
    lu.assertEquals(uiState.view.FilterMode, "all")
end

function TestUiState:testResetRestoresTransientAliasDefault()
    local config = { Enabled = true }
    local store = lib.store.create(config, makeTransientDefinition())
    local uiState = store.uiState

    uiState.set("FilterText", "Hermes")
    uiState.reset("FilterText")

    lu.assertEquals(uiState.view.FilterText, "")
    lu.assertFalse(uiState.isDirty())
end

function TestUiState:testResetRestoresPersistedAliasDefaultAndMarksDirty()
    local config = { Enabled = true, MaxGodsPerRun = 5 }
    local store = lib.store.create(config, makeScalarDefinition())
    local uiState = store.uiState

    uiState.reset("Enabled")

    lu.assertFalse(uiState.view.Enabled)
    lu.assertTrue(uiState.isDirty())

    uiState.flushToConfig()
    lu.assertFalse(config.Enabled)
end

function TestUiState:testResetRestoresPackedChildDefault()
    local config = { Packed = 0 }
    local store = lib.store.create(config, makePackedDefinition())
    local uiState = store.uiState

    uiState.set("EnabledBit", true)
    uiState.set("ModeBits", 3)
    uiState.reset("ModeBits")

    lu.assertEquals(uiState.view.ModeBits, 0)
    lu.assertTrue(uiState.view.EnabledBit)
    lu.assertEquals(uiState.view.Packed, 1)
end

function TestUiState:testRunDerivedTextUpdatesTransientStringAlias()
    local config = { Enabled = false }
    local store = lib.store.create(config, makeTransientDefinition())
    local uiState = store.uiState

    local changed = lib.host.runDerivedText(uiState, {
        {
            alias = "SummaryText",
            compute = function(state)
                return state.view.FilterText == "" and "No filter" or ("Filter: " .. state.view.FilterText)
            end,
        },
    }, {})

    lu.assertTrue(changed)
    lu.assertEquals(uiState.view.SummaryText, "No filter")

    uiState.set("FilterText", "Apollo")
    changed = lib.host.runDerivedText(uiState, {
        {
            alias = "SummaryText",
            compute = function(state)
                return state.view.FilterText == "" and "No filter" or ("Filter: " .. state.view.FilterText)
            end,
        },
    }, {})

    lu.assertTrue(changed)
    lu.assertEquals(uiState.view.SummaryText, "Filter: Apollo")
end

function TestUiState:testRunDerivedTextSkipsRecomputeWhenSignatureIsStable()
    local config = { Enabled = false }
    local store = lib.store.create(config, makeTransientDefinition())
    local uiState = store.uiState
    local cache = {}
    local computeCalls = 0

    local entries = {
        {
            alias = "SummaryText",
            signature = function(state)
                return state.view.FilterMode
            end,
            compute = function(state)
                computeCalls = computeCalls + 1
                return "Mode: " .. tostring(state.view.FilterMode)
            end,
        },
    }

    local changed = lib.host.runDerivedText(uiState, entries, cache)
    lu.assertTrue(changed)
    lu.assertEquals(uiState.view.SummaryText, "Mode: all")
    lu.assertEquals(computeCalls, 1)

    changed = lib.host.runDerivedText(uiState, entries, cache)
    lu.assertFalse(changed)
    lu.assertEquals(computeCalls, 1)

    uiState.set("FilterMode", "checked")
    changed = lib.host.runDerivedText(uiState, entries, cache)
    lu.assertTrue(changed)
    lu.assertEquals(uiState.view.SummaryText, "Mode: checked")
    lu.assertEquals(computeCalls, 2)
end
