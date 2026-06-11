local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestModuleState_DataDefaults = {}

function TestModuleState_DataDefaults:setUp()
    self.harness = createLibHarness()
end

function TestModuleState_DataDefaults:tearDown()
    self.harness = nil
end

local function makeStore(harness, definition, config, opts)
    config = config or {}
    definition.id = definition.id or "DataDefaults"
    definition.name = definition.name or "Data Defaults"
    if not (type(definition) == "table" and rawget(definition, "_preparedDefinition") == true) then
        definition = harness.managedModule.prepareDefinition({}, definition)
    end
    local state = harness.moduleState.create(config, definition, opts)
    return state.persistentState, state.stagedState, config
end

local function makeChalkConfig(harness, opts)
    opts = opts or {}
    local entries = {}
    local raw = {
        entries = entries,
        bindAttempts = {},
        config_file_path = opts.configPath,
        saved = 0,
    }

    if opts.entriesAsNonTable == true then
        raw.entries = function() end
        debug.setmetatable(raw.entries, {
            __pairs = function()
                return pairs(entries)
            end,
        })
    end

    local function getMaterializedValue(section, key, defaultValue)
        local valuesByPath = opts.materializedValuesByPath
        if valuesByPath then
            local value = valuesByPath[section .. "." .. key]
            if value ~= nil then
                return value
            end
        end
        local valuesByKey = opts.materializedValues
        if valuesByKey and valuesByKey[key] ~= nil then
            return valuesByKey[key]
        end
        return defaultValue
    end

    function raw:bind(section, key, defaultValue, description)
        self.bindAttempts[#self.bindAttempts + 1] = {
            section = section,
            key = key,
            value = defaultValue,
        }
        for descriptor in pairs(entries) do
            if descriptor.section == section and descriptor.key == key then
                error("duplicate config bind")
            end
        end

        local entry = {
            value = getMaterializedValue(section, key, defaultValue),
            description = description or "",
        }
        function entry.get(entrySelf)
            return entrySelf.value
        end
        function entry.set(entrySelf, value)
            entrySelf.value = value
        end

        entries[{ section = section, key = key }] = entry
        return entry
    end

    function raw:save()
        self.saved = self.saved + 1
    end

    local rawConfig = raw
    if opts.rawAsNonTable == true then
        rawConfig = function() end
        debug.setmetatable(rawConfig, { __index = raw, __newindex = raw })
    end

    local wrapper = { __raw = rawConfig }
    local chalk = harness.chalk
    local previousOriginal = chalk.original
    chalk.original = function(config)
        return config.__raw
    end

    return wrapper, raw, function()
        chalk.original = previousOriginal
    end
end

local function collectRawValues(raw)
    local valuesByPath = {}
    for descriptor, entry in pairs(raw.entries) do
        valuesByPath[descriptor.section .. "." .. descriptor.key] = entry:get()
    end
    return valuesByPath
end

local function writeTempConfig(contents)
    local path = os.tmpname()
    local file = assert(io.open(path, "w"))
    file:write(contents)
    file:close()
    return path
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

function TestModuleState_DataDefaults:testChalkBackendReReadsMaterializedValueAfterEnsure()
    local wrapper, raw, restore = makeChalkConfig(self.harness, {
        materializedValues = {
            MyFlag = true,
        },
    })
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = false },
        },
    }

    local persistentState, stagedState = makeStore(self.harness, definition, wrapper)
    restore()

    lu.assertTrue(persistentState.read("MyFlag"))
    lu.assertTrue(stagedState.read("MyFlag"))
    local boundMyFlag = false
    for _, attempt in ipairs(raw.bindAttempts) do
        if attempt.key == "MyFlag" then
            boundMyFlag = true
        end
    end
    lu.assertTrue(boundMyFlag)
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

function TestModuleState_DataDefaults:testChalkBackendAcceptsNonTableRawConfig()
    local wrapper, raw, restore = makeChalkConfig(self.harness, { rawAsNonTable = true })
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = false },
        },
    }

    local _, stagedState = makeStore(self.harness, definition, wrapper)
    local initialSaveCount = raw.saved
    stagedState.write("MyFlag", true)
    stagedState._flushToConfig()
    restore()

    local valuesByPath = collectRawValues(raw)
    lu.assertTrue(valuesByPath["config.MyFlag"])
    lu.assertTrue(raw.saved > initialSaveCount)
    lu.assertNil(wrapper.MyFlag)
end

function TestModuleState_DataDefaults:testChalkBackendAcceptsNonTableEntries()
    local wrapper, raw, restore = makeChalkConfig(self.harness, { entriesAsNonTable = true })
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = false },
        },
    }

    local _, stagedState = makeStore(self.harness, definition, wrapper)
    local initialSaveCount = raw.saved
    stagedState.write("MyFlag", true)
    stagedState._flushToConfig()
    restore()

    local valuesByPath = collectRawValues(raw)
    lu.assertTrue(valuesByPath["config.MyFlag"])
    lu.assertTrue(raw.saved > initialSaveCount)
    lu.assertNil(wrapper.MyFlag)
end

function TestModuleState_DataDefaults:testChalkBackendWritesTableDefaultsAsIndexedEntries()
    local wrapper, raw, restore = makeChalkConfig(self.harness)
    local definition = {
        storage = {
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Enabled", default = true },
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                },
            },
        },
    }

    local _, stagedState = makeStore(self.harness, definition, wrapper)
    restore()

    local rows = stagedState.table("Rows")
    lu.assertTrue(rows:read(1, "Enabled"))
    lu.assertEquals(rows:read(1, "Limit"), 2)
    lu.assertNil(wrapper.Rows)

    local valuesByPath = collectRawValues(raw)
    lu.assertEquals(valuesByPath["config.Rows._RowCount"], 1)
    lu.assertTrue(valuesByPath["config.Rows.1.Enabled"])
    lu.assertEquals(valuesByPath["config.Rows.1.Limit"], 2)

    for _, attempt in ipairs(raw.bindAttempts) do
        lu.assertNotEquals(attempt.key, "Rows")
    end
end

function TestModuleState_DataDefaults:testChalkBackendReadsTableRootsFromIndexedEntries()
    local wrapper, raw, restore = makeChalkConfig(self.harness)
    raw:bind("config.Rows.1", "Enabled", false, "")
    raw:bind("config.Rows.1", "Limit", 4, "")

    local definition = {
        storage = {
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Enabled", default = true },
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                },
            },
        },
    }

    local _, stagedState = makeStore(self.harness, definition, wrapper)
    restore()

    local rows = stagedState.table("Rows")
    lu.assertFalse(rows:read(1, "Enabled"))
    lu.assertEquals(rows:read(1, "Limit"), 4)
    lu.assertNil(wrapper.Rows)
end

function TestModuleState_DataDefaults:testChalkBackendReadsTableRowsFromRowCountMetadata()
    local wrapper, raw, restore = makeChalkConfig(self.harness, {
        materializedValuesByPath = {
            ["config.Rows._RowCount"] = 3,
            ["config.Rows.1.Enabled"] = false,
            ["config.Rows.1.Limit"] = 4,
            ["config.Rows.2.Enabled"] = true,
            ["config.Rows.2.Limit"] = 3,
            ["config.Rows.3.Enabled"] = false,
            ["config.Rows.3.Limit"] = 1,
        },
    })
    raw:bind("config.Rows", "_RowCount", 3, "")

    local definition = {
        storage = {
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                maxRows = 5,
                row = {
                    { type = "bool", alias = "Enabled", default = true },
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                },
            },
        },
    }

    local _, stagedState = makeStore(self.harness, definition, wrapper)
    restore()

    local rows = stagedState.table("Rows")
    lu.assertEquals(rows:count(), 3)
    lu.assertFalse(rows:read(1, "Enabled"))
    lu.assertEquals(rows:read(1, "Limit"), 4)
    lu.assertTrue(rows:read(2, "Enabled"))
    lu.assertEquals(rows:read(2, "Limit"), 3)
    lu.assertFalse(rows:read(3, "Enabled"))
    lu.assertEquals(rows:read(3, "Limit"), 1)
end

function TestModuleState_DataDefaults:testChalkBackendBindsRowCountBeforeReadingTable()
    local wrapper, raw, restore = makeChalkConfig(self.harness, {
        materializedValuesByPath = {
            ["config.Rows._RowCount"] = 3,
            ["config.Rows.1.Enabled"] = false,
            ["config.Rows.1.Limit"] = 4,
            ["config.Rows.2.Enabled"] = true,
            ["config.Rows.2.Limit"] = 3,
            ["config.Rows.3.Enabled"] = false,
            ["config.Rows.3.Limit"] = 1,
        },
    })

    local definition = {
        storage = {
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                maxRows = 5,
                row = {
                    { type = "bool", alias = "Enabled", default = true },
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                },
            },
        },
    }

    local _, stagedState = makeStore(self.harness, definition, wrapper)
    restore()

    local rows = stagedState.table("Rows")
    lu.assertEquals(rows:count(), 3)
    lu.assertFalse(rows:read(1, "Enabled"))
    lu.assertEquals(rows:read(1, "Limit"), 4)
    lu.assertTrue(rows:read(2, "Enabled"))
    lu.assertEquals(rows:read(2, "Limit"), 3)
    lu.assertFalse(rows:read(3, "Enabled"))
    lu.assertEquals(rows:read(3, "Limit"), 1)

    local boundRowCount = false
    for _, attempt in ipairs(raw.bindAttempts) do
        if attempt.section == "config.Rows" and attempt.key == "_RowCount" then
            boundRowCount = true
        end
    end
    lu.assertTrue(boundRowCount)
end

function TestModuleState_DataDefaults:testNativeBackendHydratesFlatConfigWithoutBinding()
    local path = writeTempConfig([[
## Settings file was created by plugin SGG_Modding-Chalk

[config]
Enabled = true
DebugMode = false
AdamantFramework_PackRestoreSnapshot = 0
MyFlag = false
MyCount = 8

[config.Rows]
_RowCount = 2

[config.Rows.1]
Enabled = false
Limit = 4

[config.Rows.2]
Enabled = true
Limit = 3
]])
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
            { type = "int", alias = "MyCount", default = 1, min = 0, max = 10 },
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                maxRows = 5,
                row = {
                    { type = "bool", alias = "Enabled", default = true },
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                },
            },
        },
    }

    local previousOriginal = self.harness.chalk.original
    self.harness.chalk.original = function()
        error("native backend should not call Chalk")
    end
    local ok, _, stagedState = pcall(function()
        return makeStore(self.harness, definition, {}, {
            configPath = path,
        })
    end)
    self.harness.chalk.original = previousOriginal
    lu.assertTrue(ok)
    lu.assertFalse(stagedState.read("MyFlag"))
    lu.assertEquals(stagedState.read("MyCount"), 8)
    lu.assertEquals(stagedState.table("Rows"):count(), 2)
    lu.assertFalse(stagedState.table("Rows"):read(1, "Enabled"))
    lu.assertEquals(stagedState.table("Rows"):read(1, "Limit"), 4)
    lu.assertTrue(stagedState.table("Rows"):read(2, "Enabled"))
    lu.assertEquals(stagedState.table("Rows"):read(2, "Limit"), 3)

    stagedState.write("MyFlag", true)
    stagedState._flushToConfig()

    local file = assert(io.open(path, "r"))
    local saved = file:read("*a")
    file:close()
    os.remove(path)
    lu.assertStrContains(saved, "MyFlag = true")
end

function TestModuleState_DataDefaults:testChalkBackendFlushesTableRootsAsIndexedEntries()
    local wrapper, raw, restore = makeChalkConfig(self.harness)
    local definition = {
        storage = {
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Enabled", default = true },
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                },
            },
        },
    }

    local _, stagedState = makeStore(self.harness, definition, wrapper)
    local initialSaveCount = raw.saved
    stagedState.table("Rows"):write(1, "Limit", 4)
    stagedState._flushToConfig()
    restore()

    local valuesByPath = collectRawValues(raw)
    lu.assertTrue(raw.saved > initialSaveCount)
    lu.assertEquals(valuesByPath["config.Rows._RowCount"], 1)
    lu.assertTrue(valuesByPath["config.Rows.1.Enabled"])
    lu.assertEquals(valuesByPath["config.Rows.1.Limit"], 4)
    lu.assertNil(wrapper.Rows)
end

function TestModuleState_DataDefaults:testChalkBackendBatchesHydrationSaves()
    local wrapper, raw, restore = makeChalkConfig(self.harness)
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
            { type = "int", alias = "MyCount", default = 4, min = 0, max = 10 },
            { type = "string", alias = "MyMode", default = "Auto" },
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Enabled", default = true },
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                },
            },
        },
    }

    local _, stagedState = makeStore(self.harness, definition, wrapper)
    restore()

    lu.assertTrue(stagedState.read("MyFlag"))
    lu.assertEquals(stagedState.read("MyCount"), 4)
    lu.assertEquals(stagedState.read("MyMode"), "Auto")
    lu.assertTrue(stagedState.table("Rows"):read(1, "Enabled"))
    lu.assertEquals(stagedState.table("Rows"):read(1, "Limit"), 2)
    lu.assertEquals(raw.saved, 1)
end

function TestModuleState_DataDefaults:testHydrationDoesNotRewriteSemanticallyEqualTableConfig()
    local writes = {}
    local row = {}
    setmetatable(row, {
        __index = function(_, key)
            if key == "Enabled" then
                return true
            elseif key == "Limit" then
                return 2
            end
            return nil
        end,
        __pairs = function()
            return pairs({
                Enabled = true,
                Limit = 2,
            })
        end,
    })

    local rows = {}
    setmetatable(rows, {
        __len = function()
            return 1
        end,
        __index = function(_, key)
            if key == 1 then
                return row
            end
            return nil
        end,
        __pairs = function()
            return pairs({ row })
        end,
    })

    local config = {}
    setmetatable(config, {
        __index = function(_, key)
            if key == "Rows" then
                return rows
            end
            return nil
        end,
        __newindex = function(_, key, value)
            writes[#writes + 1] = {
                key = key,
                value = value,
            }
        end,
    })

    local definition = {
        storage = {
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Enabled", default = true },
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                },
            },
        },
    }

    local _, stagedState = makeStore(self.harness, definition, config)

    lu.assertTrue(stagedState.table("Rows"):read(1, "Enabled"))
    lu.assertEquals(stagedState.table("Rows"):read(1, "Limit"), 2)
    for _, write in ipairs(writes) do
        lu.assertNotEquals(write.key, "Rows")
    end
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
    lu.assertEquals(raw.saved, 1)

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
    local definition = self.harness.managedModule.prepareDefinition({}, {
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

