local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestModuleState_DataDefaults = {}

function TestModuleState_DataDefaults:setUp()
    self.harness = createLibHarness()
end

function TestModuleState_DataDefaults:tearDown()
    self.harness = nil
end

local function makeStore(harness, definition, config)
    config = config or {}
    definition.id = definition.id or "DataDefaults"
    definition.name = definition.name or "Data Defaults"
    if not (type(definition) == "table" and rawget(definition, "_preparedDefinition") == true) then
        definition = harness.moduleHost.prepareDefinition({}, definition)
    end
    local state = harness.moduleState.create(config, definition)
    return state.persistentState, state.stagedState, config
end

local function makeChalkConfig(harness)
    local raw = {
        entries = {},
        saved = 0,
    }

    function raw:bind(section, key, defaultValue, description)
        for descriptor in pairs(self.entries) do
            if descriptor.section == section and descriptor.key == key then
                error("duplicate config bind")
            end
        end

        local entry = {
            value = defaultValue,
            description = description or "",
        }
        function entry.get(entrySelf)
            return entrySelf.value
        end
        function entry.set(entrySelf, value)
            entrySelf.value = value
        end

        self.entries[{ section = section, key = key }] = entry
        return entry
    end

    function raw:save()
        self.saved = self.saved + 1
    end

    local wrapper = { __raw = raw }
    local chalk = harness.chalk
    local previousOriginal = chalk.original
    chalk.original = function(config)
        return config.__raw
    end

    return wrapper, raw, function()
        chalk.original = previousOriginal
    end
end

function TestModuleState_DataDefaults:testUsesBoolStorageDefault()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
        },
    }
    local _, stagedState = makeStore(self.harness, definition, {})

    lu.assertTrue(stagedState.read("MyFlag"))
end

function TestModuleState_DataDefaults:testUsesIntStorageDefault()
    local definition = {
        storage = {
            { type = "int", alias = "MyCount", default = 7, min = 0, max = 10 },
        },
    }
    local _, stagedState = makeStore(self.harness, definition, {})

    lu.assertEquals(stagedState.read("MyCount"), 7)
end

function TestModuleState_DataDefaults:testUsesStringStorageDefault()
    local definition = {
        storage = {
            { type = "string", alias = "MyChoice", default = "Forced" },
        },
    }
    local _, stagedState = makeStore(self.harness, definition, {})

    lu.assertEquals(stagedState.read("MyChoice"), "Forced")
end

-- Live config value overrides the default when present
function TestModuleState_DataDefaults:testLiveConfigValueOverridesDefault()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
        },
    }
    local _, stagedState = makeStore(self.harness, definition, { MyFlag = false })

    lu.assertFalse(stagedState.read("MyFlag"))
end

function TestModuleState_DataDefaults:testChalkBackendSavesStagedWrites()
    local wrapper, raw, restore = makeChalkConfig(self.harness)
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = false },
        },
    }

    local _, stagedState = makeStore(self.harness, definition, wrapper)
    local initialSaveCount = raw.saved
    lu.assertTrue(initialSaveCount >= 1)

    stagedState.write("MyFlag", true)
    stagedState._flushToConfig()

    lu.assertTrue(raw.saved > initialSaveCount)
    restore()
end

function TestModuleState_DataDefaults:testMissingStorageDefaultFails()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag" },
        },
    }
    lu.assertErrorMsgContains("must declare an effective default", function()
        makeStore(self.harness, definition, {})
    end)
end

function TestModuleState_DataDefaults:testMissingTableRowDefaultFails()
    local definition = {
        storage = {
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Flag" },
                },
            },
        },
    }
    lu.assertErrorMsgContains("must declare an effective default", function()
        makeStore(self.harness, definition, {})
    end)
end

function TestModuleState_DataDefaults:testNestedTableStorageFails()
    local definition = {
        storage = {
            {
                type = "table",
                alias = "Rows",
                row = {
                    {
                        type = "table",
                        alias = "Nested",
                        row = {
                            { type = "bool", alias = "Flag", default = false },
                        },
                    },
                },
            },
        },
    }
    lu.assertErrorMsgContains("nested table storage is not supported", function()
        makeStore(self.harness, definition, {})
    end)
end

function TestModuleState_DataDefaults:testExplicitStorageDefaultsAreSafe()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
        },
    }
    local _, stagedState = makeStore(self.harness, definition, {})

    lu.assertTrue(stagedState.read("MyFlag"))
end

function TestModuleState_DataDefaults:testCreateStoreHydratesMissingConfigFromStorageDefault()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
            { type = "int", alias = "MyCount", default = 4, min = 0, max = 10 },
            { type = "string", alias = "MyMode", default = "Auto" },
            {
                type = "packedInt",
                alias = "PackedChoices",
                width = 2,
                default = 2,
                bits = {
                    { alias = "PackedChoiceA", offset = 0, width = 1, type = "bool", default = false },
                    { alias = "PackedChoiceB", offset = 1, width = 1, type = "bool", default = true },
                },
            },
        },
    }
    local _, stagedState, config = makeStore(self.harness, definition, {})

    lu.assertTrue(stagedState.read("MyFlag"))
    lu.assertEquals(stagedState.read("MyCount"), 4)
    lu.assertEquals(stagedState.read("MyMode"), "Auto")
    lu.assertEquals(stagedState.read("PackedChoices"), 2)
    lu.assertEquals(config.MyFlag, true)
    lu.assertEquals(config.MyCount, 4)
    lu.assertEquals(config.MyMode, "Auto")
    lu.assertEquals(config.PackedChoices, 2)
end

function TestModuleState_DataDefaults:testCreateStoreDoesNotHydrateTransientStorageIntoConfig()
    local definition = {
        storage = {
            { type = "bool", alias = "RecordingArmed", default = false, persist = false, hash = false },
            { type = "int", alias = "RunMarker", default = 3, min = 0, max = 10, persist = false, hash = false },
        },
    }
    local store, stagedState, config = makeStore(self.harness, definition, {})

    lu.assertFalse(stagedState.read("Enabled"))
    lu.assertFalse(stagedState.read("RecordingArmed"))
    lu.assertEquals(stagedState.read("RunMarker"), 3)
    lu.assertErrorMsgContains("store.invalid_surface", function()
        store.read("RecordingArmed")
    end)
    lu.assertEquals(config.Enabled, false)
    lu.assertNil(config.RecordingArmed)
    lu.assertNil(config.RunMarker)
end

function TestModuleState_DataDefaults:testCreateStorePreservesExistingConfigValues()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
            { type = "int", alias = "MyCount", default = 4, min = 0, max = 10 },
        },
    }
    local _, stagedState, config = makeStore(self.harness, definition, { MyFlag = false, MyCount = 9 })

    lu.assertFalse(stagedState.read("MyFlag"))
    lu.assertEquals(stagedState.read("MyCount"), 9)
    lu.assertEquals(config.MyFlag, false)
    lu.assertEquals(config.MyCount, 9)
end

function TestModuleState_DataDefaults:testCreateStoreHydratesAliasBackedConfig()
    local definition = {
        storage = {
            { type = "bool", alias = "GodModeEnabled", default = true },
            { type = "int", alias = "FixedValue", default = 3, min = 0, max = 10 },
        },
    }
    local _, stagedState, config = makeStore(self.harness, definition, {})

    lu.assertTrue(stagedState.read("GodModeEnabled"))
    lu.assertEquals(stagedState.read("FixedValue"), 3)
    lu.assertEquals(config.GodModeEnabled, true)
    lu.assertEquals(config.FixedValue, 3)
end

function TestModuleState_DataDefaults:testCreateStoreHydratesMissingChalkEntryFromStorageDefault()
    local config, raw, restoreChalk = makeChalkConfig(self.harness)
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
            { type = "int", alias = "FixedValue", default = 3, min = 0, max = 10 },
        },
    }

    local ok, _, stagedState = pcall(function()
        return makeStore(self.harness, definition, config)
    end)
    restoreChalk()

    lu.assertTrue(ok)
    lu.assertTrue(stagedState.read("MyFlag"))
    lu.assertEquals(stagedState.read("FixedValue"), 3)
    lu.assertEquals(raw.saved, 5)

    local valuesByPath = {}
    for descriptor, entry in pairs(raw.entries) do
        valuesByPath[descriptor.section .. "." .. descriptor.key] = entry:get()
    end
    lu.assertEquals(valuesByPath["config.Enabled"], false)
    lu.assertEquals(valuesByPath["config.DebugMode"], false)
    lu.assertEquals(valuesByPath["config.AdamantFramework_PackRestoreSnapshot"], 0)
    lu.assertEquals(valuesByPath["config.MyFlag"], true)
    lu.assertEquals(valuesByPath["config.FixedValue"], 3)
end

function TestModuleState_DataDefaults:testLookupUsesAliasAsBackingKey()
    local definition = {
        storage = {
            { type = "int", alias = "MyAlias", default = 0, min = 0, max = 10 },
        },
    }
    local _, stagedState = makeStore(self.harness, definition, { MyAlias = 1, OldBackingKey = 9 })

    lu.assertEquals(stagedState.read("MyAlias"), 1)
end

function TestModuleState_DataDefaults:testMissingAliasUsesStorageDefault()
    local definition = {
        storage = {
            { type = "bool", alias = "GodModeEnabled", default = true },
            { type = "int",  alias = "FixedValue", default = 3, min = 0, max = 10 },
        },
    }
    local _, stagedState = makeStore(self.harness, definition, {})

    lu.assertTrue(stagedState.read("GodModeEnabled"))
    lu.assertEquals(stagedState.read("FixedValue"), 3)
end

function TestModuleState_DataDefaults:testPreparedStorageDefaultsAreStableAcrossCreateStoreCalls()
    local definition = self.harness.moduleHost.prepareDefinition({}, {
        id = "StablePreparedDefaults",
        name = "Stable Prepared Defaults",
        storage = {
            { type = "int", alias = "MyCount", default = 5, min = 0, max = 10 },
        },
    })

    lu.assertEquals(definition.storage[4].default, 5)

    makeStore(self.harness, definition, {})
    lu.assertEquals(definition.storage[4].default, 5)
end

-- Multiple nodes all receive their storage defaults.
function TestModuleState_DataDefaults:testMultipleNodesAllFilled()
    local definition = {
        storage = {
            { type = "bool",   alias = "FlagA", default = true },
            { type = "int",    alias = "Count", default = 5, min = 0, max = 20 },
            { type = "string", alias = "Mode", default = "Vanilla" },
        },
    }
    local _, stagedState = makeStore(self.harness, definition, {})

    lu.assertTrue(stagedState.read("FlagA"))
    lu.assertEquals(stagedState.read("Count"), 5)
    lu.assertEquals(stagedState.read("Mode"), "Vanilla")
end

