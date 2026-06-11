local deps = ...

local logging = deps.logging
local backendMetrics = {}
local DIAGNOSTIC_SUBSYSTEM = "configBackend"

local SUMMARY_FIELDS = {
    { "reads", "reads" },
    { "read_tables", "read_tables" },
    { "row_count_hits", "row_count_hits" },
    { "row_count_misses", "row_count_misses" },
    { "fallback_scans", "fallback_scans" },
    { "fallback_sections", "fallback_sections_scanned" },
    { "get_entries", "get_entries" },
    { "get_hits", "get_entry_hits" },
    { "get_misses", "get_entry_misses" },
    { "entry_gets", "entry_gets" },
    { "entry_sets", "entry_sets" },
    { "binds", "binds" },
    { "bind_failures", "bind_failures" },
    { "bind_time_ms", "bind_time_ms", "%.3f" },
    { "bind_slow", "bind_slow" },
    { "parse_time_ms", "parse_time_ms", "%.3f" },
    { "save_time_ms", "save_time_ms", "%.3f" },
    { "write_scalar_time_ms", "write_scalar_time_ms", "%.3f" },
    { "write_table_time_ms", "write_table_time_ms", "%.3f" },
    { "write_table_row_count_time_ms", "write_table_row_count_time_ms", "%.3f" },
    { "write_table_cells_time_ms", "write_table_cells_time_ms", "%.3f" },
    { "write_table_prune_time_ms", "write_table_prune_time_ms", "%.3f" },
    { "write_tables", "write_tables" },
    { "table_cells", "table_cells" },
    { "table_cell_changes", "table_cell_changes" },
    { "prune_scans", "prune_scans" },
    { "prune_sections", "prune_sections_scanned" },
    { "prune_entries", "prune_entries_scanned" },
    { "saves", "saves" },
}

local function isEnabled()
    return logging.isDiagnosticEnabled(DIAGNOSTIC_SUBSYSTEM)
end

local function snapshotCounters(counters)
    local snapshot = {}
    for key, value in pairs(counters) do
        snapshot[key] = value
    end
    return snapshot
end

local function deltaCounter(counters, snapshot, key)
    snapshot = snapshot or {}
    return (counters[key] or 0) - (snapshot[key] or 0)
end

local function formatCounter(value, format)
    if format then
        return string.format(format, value or 0)
    end
    return tostring(value or 0)
end

local function appendSummaryFields(parts, counters, scope)
    for _, field in ipairs(SUMMARY_FIELDS) do
        local label = field[1]
        local key = field[2]
        local format = field[3]
        parts[#parts + 1] = label .. "=" .. formatCounter(deltaCounter(counters, scope, key), format)
    end
end

function backendMetrics.create(backendName)
    local metrics = {}
    local counters = {}

    function metrics.isEnabled()
        return isEnabled()
    end

    function metrics.count(key, amount)
        counters[key] = (counters[key] or 0) + (amount or 1)
    end

    function metrics.diagnose(fmt, ...)
        return logging.diagnose(DIAGNOSTIC_SUBSYSTEM, fmt, ...)
    end

    function metrics.beginScope()
        if not isEnabled() then
            return nil
        end
        return snapshotCounters(counters)
    end

    function metrics.printScope(label, phase, scope, entryCount, sectionCount)
        if not isEnabled() then
            return
        end

        local parts = {
            "config backend summary",
            "backend=" .. tostring(backendName or "unknown"),
            "module=" .. tostring(label or "module"),
            "phase=" .. tostring(phase or "scope"),
            "entries=" .. tostring(entryCount or 0),
            "sections=" .. tostring(sectionCount or 0),
        }
        appendSummaryFields(parts, counters, scope)
        logging.diagnose(DIAGNOSTIC_SUBSYSTEM, table.concat(parts, " "))
    end

    return metrics
end

return backendMetrics
