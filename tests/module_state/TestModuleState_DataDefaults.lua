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
    opts = opts or {}
    definition.id = definition.id or "DataDefaults"
    definition.name = definition.name or "Data Defaults"
    if not (type(definition) == "table" and rawget(definition, "_preparedDefinition") == true) then
        definition = harness.managedModule.prepareDefinition({}, definition)
    end
    local persistentState, stagedState = harness:createModuleState(config, definition, opts)
    return persistentState, stagedState, config
end

local function writeTempConfig(contents)
    local path = os.tmpname()
    local file = assert(io.open(path, "w"))
    file:write(contents)
    file:close()
    return path
end

local function capturePrints(env, callback)
    local lines = {}
    local previousPrint = env.print
    env.print = function(message)
        lines[#lines + 1] = message
    end
    local ok, err = pcall(callback, lines)
    env.print = previousPrint
    if not ok then
        error(err, 0)
    end
    return lines
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

function TestModuleState_DataDefaults:testWarnsWhenNativeBackendPathCannotResolve()
    local backendFactory = self.harness.import("core/module_state/persistent/backend_factory.lua", nil, {
        logging = self.harness.logging,
        rom = {},
    })

    local lines = capturePrints(self.harness.env, function()
        local backend = backendFactory.create({
            pluginGuid = "test-missing-native-path",
        })
        lu.assertNil(backend)
    end)

    lu.assertEquals(#lines, 1)
    lu.assertStrContains(lines[1], "[lib] persistent_backend.unavailable:")
    lu.assertStrContains(lines[1], "test-missing-native-path")
    lu.assertStrContains(lines[1], "will not persist")
end

function TestModuleState_DataDefaults:testWarnsWhenNativeBackendCannotSave()
    local backendMetrics = self.harness.import("core/module_state/persistent/backend_metrics.lua", nil, {
        logging = self.harness.logging,
    })
    local nativeBackend = self.harness.import("core/module_state/persistent/native_backend.lua", nil, {
        metrics = backendMetrics,
        logging = self.harness.logging,
    })
    local backend = nativeBackend.create({
        path = self.harness.nativeConfigRoot .. "/missing-parent/config.cfg",
    })
    lu.assertNotNil(backend)

    local lines = capturePrints(self.harness.env, function()
        lu.assertTrue(backend.write("config", "MyFlag", true))
    end)

    lu.assertEquals(#lines, 1)
    lu.assertStrContains(lines[1], "[lib] persistent_backend.save_failed:")
    lu.assertStrContains(lines[1], "may not persist")
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

