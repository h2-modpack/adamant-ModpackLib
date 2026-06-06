local createLibHarness = require('tests/harness/create_lib_harness')

local helpers = {}
helpers.createLibHarness = createLibHarness

function helpers.prepareDefinition(harness, definition)
    definition.id = definition.id or "StagedStateTest"
    definition.name = definition.name or "stagedState Test"
    return harness.managedModule.prepareDefinition({}, definition)
end

function helpers.createModuleState(harness, config, definition)
    local state = harness.moduleState.create(config, definition)
    return state.persistentState, state.stagedState
end

function helpers.getHostLifecycle(harness)
    return assert(harness.imports["core/module_bootstrap/managed_module_lifecycle.lua"],
        "managed module lifecycle service missing")
end

function helpers.withLoggingPolicy(policy, callback)
    local harness = createLibHarness({
        importOverrides = {
            ["core/logging/policies.lua"] = policy,
        },
    })
    return callback(harness)
end

function helpers.withCapturedPrint(harness, callback)
    local previousPrint = harness.env.print
    local lines = {}
    harness.config.DebugMode = true
    harness.env.print = function(msg)
        lines[#lines + 1] = msg
    end

    local ok, err = pcall(callback, lines)
    harness.env.print = previousPrint
    harness.config.DebugMode = false
    if not ok then
        error(err, 0)
    end
    return lines
end

function helpers.makeScalarDefinition(harness)
    return helpers.prepareDefinition(harness, {
        storage = {
            { type = "int", alias = "MaxGods", default = 3, min = 1, max = 9 },
        },
    })
end

function helpers.makePackedDefinition(harness)
    return helpers.prepareDefinition(harness, {
        storage = {
            {
                type = "packedInt",
                alias = "Packed",
                width = 3,
                bits = {
                    { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = false },
                    { alias = "ModeBits", offset = 1, width = 2, type = "int", default = 0 },
                },
            },
        },
    })
end

function helpers.makeTransientDefinition(harness)
    return helpers.prepareDefinition(harness, {
        storage = {
            { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
            { type = "string", alias = "FilterMode", persist = false, hash = false, default = "all", maxLen = 16 },
            { type = "string", alias = "SummaryText", persist = false, hash = false, default = "", maxLen = 128 },
        },
    })
end

function helpers.makeRuntimeDefinition(harness, opts)
    opts = opts or {}
    return helpers.prepareDefinition(harness, {
        storage = {
            { type = "bool", alias = "RuntimeFlag", mode = "runtime", persist = opts.persist, default = false },
            { type = "int", alias = "RuntimeCount", mode = "runtime", persist = opts.persist, default = 0, min = 0, max = 5 },
            {
                type = "packedInt",
                alias = "RuntimePacked",
                width = 1,
                mode = "runtime",
                persist = opts.persist,
                bits = {
                    { alias = "RuntimeBit", offset = 0, width = 1, type = "bool", default = false },
                },
            },
            {
                type = "table",
                alias = "RuntimeRows",
                mode = "runtime",
                persist = opts.persist,
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Enabled", default = false },
                },
            },
            { type = "bool", alias = "SettingFlag", default = false },
        },
    })
end

function helpers.makeTableDefinition(harness)
    return helpers.prepareDefinition(harness, {
        storage = {
            {
                type = "table",
                alias = "Tiers",
                minRows = 0,
                maxRows = 3,
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Enabled", default = true },
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                    { type = "string", alias = "Note", default = "", maxLen = 64 },
                    {
                        type = "packedInt",
                        alias = "PackedChoices",
                        width = 3,
                        bits = {
                            { alias = "ChoiceA", offset = 0, width = 1, type = "bool", default = false },
                            { alias = "ChoiceMode", offset = 1, width = 2, type = "int", default = 0 },
                        },
                    },
                },
            },
        },
    })
end

function helpers.makeMinRowsTableDefinition(harness)
    return helpers.prepareDefinition(harness, {
        storage = {
            {
                type = "table",
                alias = "Rows",
                minRows = 1,
                maxRows = 2,
                defaultRows = 1,
                row = {
                    { type = "int", alias = "Count", default = 0, min = 0, max = 5 },
                },
            },
        },
    })
end

return helpers
