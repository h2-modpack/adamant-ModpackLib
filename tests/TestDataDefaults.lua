local lu = require('luaunit')

-- =============================================================================
-- getPackWidth
-- =============================================================================

TestGetPackWidth = {}

function TestGetPackWidth:testBoolAlwaysReturnsOne()
    lu.assertEquals(lib.hashing.getPackWidth({ type = "bool" }), 1)
end

function TestGetPackWidth:testIntDerivesFromMinMax()
    -- min=0, max=7 → range 7 → ceil(log2(8)) = 3
    lu.assertEquals(lib.hashing.getPackWidth({ type = "int", min = 0, max = 7 }), 3)
    -- min=0, max=15 → range 15 → ceil(log2(16)) = 4
    lu.assertEquals(lib.hashing.getPackWidth({ type = "int", min = 0, max = 15 }), 4)
    -- min=1, max=12 → range 11 → ceil(log2(12)) = 4
    lu.assertEquals(lib.hashing.getPackWidth({ type = "int", min = 1, max = 12 }), 4)
end

function TestGetPackWidth:testIntUsesExplicitWidthOverMinMax()
    lu.assertEquals(lib.hashing.getPackWidth({ type = "int", min = 0, max = 7, width = 5 }), 5)
end

function TestGetPackWidth:testIntWithNoMaxReturnsNil()
    lu.assertNil(lib.hashing.getPackWidth({ type = "int", min = 0 }))
end

function TestGetPackWidth:testStringReturnsNil()
    lu.assertNil(lib.hashing.getPackWidth({ type = "string" }))
end

function TestGetPackWidth:testUnknownTypeReturnsNil()
    lu.assertNil(lib.hashing.getPackWidth({ type = "unknown" }))
end

-- =============================================================================
-- dataDefaults
-- =============================================================================

TestDataDefaults = {}

local function makeStore(definition, config, dataDefaults)
    config = config or {}
    if not AdamantModpackLib_Internal.definition.isPrepared(definition) then
        definition = lib.prepareDefinition({}, dataDefaults, definition)
    end
    local store, session = lib.createStore(config, definition)
    return store, session, config
end

-- dataDefaults fills in missing defaults from configKey lookup
function TestDataDefaults:testFillsBoolDefaultFromConfigKey()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", configKey = "MyFlag" },
        },
    }
    local store, session = makeStore(definition, {}, { MyFlag = true })

    lu.assertTrue(session.read("MyFlag"))
end

function TestDataDefaults:testFillsIntDefaultFromConfigKey()
    local definition = {
        storage = {
            { type = "int", alias = "MyCount", configKey = "MyCount", min = 0, max = 10 },
        },
    }
    local store, session = makeStore(definition, {}, { MyCount = 7 })

    lu.assertEquals(session.read("MyCount"), 7)
end

function TestDataDefaults:testFillsStringDefaultFromConfigKey()
    local definition = {
        storage = {
            { type = "string", alias = "MyChoice", configKey = "MyChoice" },
        },
    }
    local store, session = makeStore(definition, {}, { MyChoice = "Forced" })

    lu.assertEquals(session.read("MyChoice"), "Forced")
end

-- Explicit default on the node takes precedence over dataDefaults
function TestDataDefaults:testExplicitDefaultTakesPrecedenceOverDataDefaults()
    local definition = {
        storage = {
            { type = "int", alias = "MyCount", configKey = "MyCount", default = 3, min = 0, max = 10 },
        },
    }
    local store, session = makeStore(definition, {}, { MyCount = 99 })

    lu.assertEquals(session.read("MyCount"), 3)
end

-- Live config value overrides the default when present
function TestDataDefaults:testLiveConfigValueOverridesDefault()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", configKey = "MyFlag" },
        },
    }
    local store, session = makeStore(definition, { MyFlag = false }, { MyFlag = true })

    lu.assertFalse(session.read("MyFlag"))
end

-- Missing key in dataDefaults leaves default as nil (storage type normalizes it)
function TestDataDefaults:testMissingKeyInDataDefaultsNormalizesToTypeDefault()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", configKey = "MyFlag" },
        },
    }
    -- dataDefaults has no MyFlag entry — bool normalizes nil to false
    local store, session = makeStore(definition, {}, {})

    lu.assertFalse(session.read("MyFlag"))
end

-- nil dataDefaults argument is safe (no error, explicit defaults still work)
function TestDataDefaults:testNilDataDefaultsIsSafe()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", configKey = "MyFlag", default = true },
        },
    }
    local store, session = makeStore(definition, {}, nil)

    lu.assertTrue(session.read("MyFlag"))
end

-- Lookup uses configKey, not alias, when both are present and differ
function TestDataDefaults:testLookupUsesConfigKeyNotAlias()
    local definition = {
        storage = {
            { type = "int", alias = "MyAlias", configKey = "MyConfigKey", min = 0, max = 10 },
        },
    }
    local store, session = makeStore(definition, {}, {
        MyAlias     = 1,  -- should be ignored
        MyConfigKey = 9,  -- should be used
    })

    lu.assertEquals(session.read("MyAlias"), 9)
end

-- Nested configKey table is traversed correctly in dataDefaults
function TestDataDefaults:testNestedConfigKeyTraversesDataDefaults()
    local definition = {
        storage = {
            { type = "bool", alias = "GodModeEnabled", configKey = { "GodMode", "Enabled" } },
            { type = "int",  alias = "FixedValue",     configKey = { "GodMode", "FixedValue" }, min = 0, max = 10 },
        },
    }
    local store, session = makeStore(definition, {}, {
        GodMode = { Enabled = true, FixedValue = 3 },
    })

    lu.assertTrue(session.read("GodModeEnabled"))
    lu.assertEquals(session.read("FixedValue"), 3)
end

-- createStore called twice on same definition (reload) does not double-apply dataDefaults
function TestDataDefaults:testIdempotentOnSecondCreateStoreCall()
    local definition = lib.prepareDefinition({}, { MyCount = 5 }, {
        storage = {
            { type = "int", alias = "MyCount", configKey = "MyCount", min = 0, max = 10 },
        },
    })

    lu.assertEquals(definition.storage[1].default, 5)

    -- Second call with different dataDefaults — prepared defaults stay fixed
    makeStore(definition, {}, { MyCount = 99 })
    lu.assertEquals(definition.storage[1].default, 5)
end

-- Multiple nodes all receive their defaults
function TestDataDefaults:testMultipleNodesAllFilled()
    local definition = {
        storage = {
            { type = "bool",   alias = "FlagA", configKey = "FlagA" },
            { type = "int",    alias = "Count",  configKey = "Count", min = 0, max = 20 },
            { type = "string", alias = "Mode",   configKey = "Mode" },
        },
    }
    local store, session = makeStore(definition, {}, {
        FlagA = true,
        Count = 5,
        Mode  = "Vanilla",
    })

    lu.assertTrue(session.read("FlagA"))
    lu.assertEquals(session.read("Count"), 5)
    lu.assertEquals(session.read("Mode"), "Vanilla")
end

