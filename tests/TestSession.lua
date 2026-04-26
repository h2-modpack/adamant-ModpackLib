local lu = require('luaunit')

local function prepareDefinition(definition)
    return lib.prepareDefinition({}, definition)
end

local function makeScalarDefinition()
    return prepareDefinition({
        storage = {
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
            { type = "int", alias = "MaxGods", configKey = "MaxGodsPerRun", default = 3, min = 1, max = 9 },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
            { type = "stepper", binds = { value = "MaxGods" }, label = "Max Gods", min = 1, max = 9, step = 1 },
        },
    })
end

local function makePackedDefinition()
    return prepareDefinition({
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
    })
end

local function makeTransientDefinition()
    return prepareDefinition({
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
    })
end

TestStore = {}

function TestStore:testCreateStoreReadsAndWritesScalarAliasesAndRawKeys()
    local config = { Enabled = false, MaxGodsPerRun = 4 }
    local store, session = lib.createStore(config, makeScalarDefinition())

    lu.assertFalse(store.read("Enabled"))
    lu.assertEquals(store.read("MaxGods"), 4)
    lu.assertEquals(store.read("MaxGodsPerRun"), 4)

    session.write("Enabled", true)
    session.write("MaxGods", 12)
    session._flushToConfig()

    lu.assertTrue(config.Enabled)
    lu.assertEquals(config.MaxGodsPerRun, 9)
    lu.assertEquals(store.read("MaxGods"), 9)
end

function TestStore:testPackedAliasReadWriteUpdatesOwningRoot()
    local config = { Packed = 0 }
    local store, session = lib.createStore(config, makePackedDefinition())

    lu.assertFalse(store.read("EnabledBit"))
    lu.assertEquals(store.read("ModeBits"), 0)
    lu.assertEquals(store.read("Packed"), 0)

    session.write("EnabledBit", true)
    session._flushToConfig()
    lu.assertEquals(config.Packed, 1)
    lu.assertTrue(store.read("EnabledBit"))

    session.write("ModeBits", 3)
    session._flushToConfig()
    lu.assertEquals(config.Packed, 7)
    lu.assertEquals(store.read("ModeBits"), 3)
end

function TestStore:testTransientAliasesAreNotReadableThroughStore()
    CaptureWarnings()
    local config = { Enabled = false }
    local store, session = lib.createStore(config, makeTransientDefinition())

    lu.assertNil(store.read("FilterText"))
    lu.assertEquals(session.view.FilterText, "")

    local sawReadWarning = false
    for _, warning in ipairs(Warnings) do
        if string.find(warning, "store.read: alias 'FilterText' is transient", 1, true) then
            sawReadWarning = true
        end
    end
    RestoreWarnings()

    lu.assertTrue(sawReadWarning)
end

TestSession = {}

function TestSession:testSessionStagesScalarAliases()
    local config = { Enabled = true, MaxGodsPerRun = 5 }
    local store, session = lib.createStore(config, makeScalarDefinition())

    lu.assertTrue(session.view.Enabled)
    lu.assertEquals(session.view.MaxGods, 5)
    lu.assertFalse(session.isDirty())

    session.write("Enabled", false)
    lu.assertTrue(session.isDirty())
    lu.assertFalse(session.view.Enabled)

    session._flushToConfig()
    lu.assertFalse(session.isDirty())
    lu.assertFalse(config.Enabled)
end

function TestSession:testPackedAliasEditReencodesPackedRootOnFlush()
    local config = { Packed = 0 }
    local store, session = lib.createStore(config, makePackedDefinition())

    session.write("ModeBits", 2)

    lu.assertTrue(session.isDirty())
    lu.assertEquals(session.view.ModeBits, 2)
    lu.assertEquals(session.view.Packed, 4)
    lu.assertEquals(config.Packed, 0)

    session._flushToConfig()

    lu.assertEquals(config.Packed, 4)
    lu.assertFalse(session.isDirty())
end

function TestSession:testInternalReloadFromConfigRebuildsPackedChildren()
    local config = { Packed = 0 }
    local store, session = lib.createStore(config, makePackedDefinition())

    config.Packed = 5
    session._reloadFromConfig()

    lu.assertEquals(session.view.Packed, 5)
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.ModeBits, 2)
end

function TestSession:testResyncSessionDetectsPackedDrift()
    local config = { Packed = 0 }
    local store, session = lib.createStore(config, makePackedDefinition())

    config.Packed = 5
    local mismatches = lib.lifecycle.resyncSession({ name = "PackedSession" }, session)

    table.sort(mismatches)
    lu.assertEquals(mismatches, { "EnabledBit", "ModeBits", "Packed" })
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.ModeBits, 2)
    lu.assertEquals(session.view.Packed, 5)
end

function TestSession:testReadonlyViewRejectsWrites()
    local config = { Enabled = true, MaxGodsPerRun = 5 }
    local store, session = lib.createStore(config, makeScalarDefinition())

    local ok, err = pcall(function()
        session.view.Enabled = false
    end)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "read-only")
end

function TestSession:testTransientAliasesLiveOnlyInSession()
    local config = { Enabled = false }
    local store, session = lib.createStore(config, makeTransientDefinition())

    lu.assertEquals(session.view.FilterText, "")
    lu.assertEquals(session.view.FilterMode, "all")
    lu.assertFalse(session.isDirty())

    session.write("FilterText", "Poseidon")
    session.write("FilterMode", "allowed")

    lu.assertEquals(session.view.FilterText, "Poseidon")
    lu.assertEquals(session.view.FilterMode, "allowed")
    lu.assertFalse(session.isDirty())

    session._flushToConfig()
    lu.assertFalse(session.isDirty())
    lu.assertNil(config.FilterText)
end

function TestSession:testInternalReloadFromConfigResetsTransientAliasesToDefaults()
    local config = { Enabled = true }
    local store, session = lib.createStore(config, makeTransientDefinition())

    session.write("FilterText", "Hera")
    session.write("FilterMode", "banned")
    config.Enabled = false

    session._reloadFromConfig()

    lu.assertFalse(session.view.Enabled)
    lu.assertEquals(session.view.FilterText, "")
    lu.assertEquals(session.view.FilterMode, "all")
end

function TestSession:testResetRestoresTransientAliasDefault()
    local config = { Enabled = true }
    local store, session = lib.createStore(config, makeTransientDefinition())

    session.write("FilterText", "Hermes")
    session.reset("FilterText")

    lu.assertEquals(session.view.FilterText, "")
    lu.assertFalse(session.isDirty())
end

function TestSession:testResetRestoresPersistedAliasDefaultAndMarksDirty()
    local config = { Enabled = true, MaxGodsPerRun = 5 }
    local store, session = lib.createStore(config, makeScalarDefinition())

    session.reset("Enabled")

    lu.assertFalse(session.view.Enabled)
    lu.assertTrue(session.isDirty())

    session._flushToConfig()
    lu.assertFalse(config.Enabled)
end

function TestSession:testResetRestoresPackedChildDefault()
    local config = { Packed = 0 }
    local store, session = lib.createStore(config, makePackedDefinition())

    session.write("EnabledBit", true)
    session.write("ModeBits", 3)
    session.reset("ModeBits")

    lu.assertEquals(session.view.ModeBits, 0)
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.Packed, 1)
end



