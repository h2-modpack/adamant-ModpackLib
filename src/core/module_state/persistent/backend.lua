local deps = ...

local chalk = deps.chalk
local backendMetrics = deps.metrics
local backendCache = setmetatable({}, { __mode = "k" })
local TABLE_ROW_COUNT_KEY = "_RowCount"
local SLOW_BIND_MS = 50

local function readField(object, key)
    local ok, value = pcall(function()
        return object[key]
    end)
    if ok then
        return value
    end
    return nil
end

local function isFlatValue(value)
    local valueType = type(value)
    return valueType == "boolean" or valueType == "number" or valueType == "string"
end

local function startsWith(value, prefix)
    return type(value) == "string" and string.sub(value, 1, #prefix) == prefix
end

local function callMethod(object, name, ...)
    local method = readField(object, name)
    if type(method) ~= "function" then
        return false, nil
    end
    local ok, result = pcall(method, object, ...)
    if ok then
        return true, result
    end
    return false, nil
end

local function nowMs()
    return os.clock() * 1000
end

local function create(config)
    if not chalk then
        return nil
    end

    local ok, rawConfig = pcall(chalk.original, config)
    if not ok or rawConfig == nil then
        return nil
    end

    local entries = readField(rawConfig, "entries")
    if type(entries) ~= "table" then
        local pairOk = pcall(function()
            return pairs(entries)
        end)
        if not pairOk then
            return nil
        end
    end

    local backend = backendCache[rawConfig]
    if backend then
        return backend
    end

    local metrics = backendMetrics.create("chalk")
    local entryIndex = {}
    for descriptor, entry in pairs(entries) do
        local section = descriptor.section
        local key = descriptor.key
        if section ~= nil and key ~= nil then
            local sectionEntries = entryIndex[section]
            if not sectionEntries then
                sectionEntries = {}
                entryIndex[section] = sectionEntries
            end
            sectionEntries[key] = entry
        end
    end

    local pathEntryCache = {}
    local saveBatchDepth = 0
    local savePending = false
    backend = {}
    local requestSave

    local function makeCacheKey(section, key)
        return tostring(section) .. "\0" .. tostring(key)
    end

    local function getTableRootKey(node)
        return type(node) == "table" and (node._storageKey or node.alias) or nil
    end

    local function getTableRowRoots(node)
        local rowSchema = type(node) == "table" and type(node.row) == "table" and node.row or nil
        if not rowSchema then
            return {}
        end
        return rawget(rowSchema, "_rootNodes") or {}
    end

    local function indexEntry(section, key, entry)
        local sectionEntries = entryIndex[section]
        if not sectionEntries then
            sectionEntries = {}
            entryIndex[section] = sectionEntries
        end
        sectionEntries[key] = entry
        pathEntryCache[makeCacheKey(section, key)] = entry
    end

    local function bindEntry(section, key, value)
        if type(section) ~= "string" or section == "" or type(key) ~= "string" or key == ""
            or not isFlatValue(value) or type(readField(rawConfig, "bind")) ~= "function" then
            return nil
        end

        metrics.count("binds")
        local bindStartedMs = nowMs()
        local bindOk, entry = callMethod(rawConfig, "bind", section, key, value, "")
        local bindElapsedMs = nowMs() - bindStartedMs
        metrics.count("bind_time_ms", bindElapsedMs)
        if metrics.isEnabled() and bindElapsedMs >= SLOW_BIND_MS then
            metrics.count("bind_slow")
            metrics.diagnose("backend slow bind section=%s key=%s elapsed_ms=%.3f",
                tostring(section),
                tostring(key),
                bindElapsedMs)
        end
        if not bindOk or not entry then
            metrics.count("bind_failures")
            return nil
        end

        indexEntry(section, key, entry)
        return entry
    end

    local function normalizeRowCount(value)
        local count = tonumber(value)
        if count == nil then
            return nil
        end
        count = math.floor(count)
        if count < 0 then
            return nil
        end
        return count
    end

    local function getTableRootSection(section, rootKey)
        return section .. "." .. rootKey
    end

    local function readRowCount(section, rootKey)
        local entry = backend.getEntry(getTableRootSection(section, rootKey), TABLE_ROW_COUNT_KEY)
        if not entry then
            metrics.count("row_count_misses")
            return nil
        end

        metrics.count("entry_gets")
        local getOk, value = callMethod(entry, "get")
        if not getOk then
            metrics.count("row_count_misses")
            return nil
        end
        local rowCount = normalizeRowCount(value)
        if rowCount == nil then
            metrics.count("row_count_misses")
            return nil
        end
        metrics.count("row_count_hits")
        return rowCount
    end

    local function readBoundRowCount(section, rootKey, defaultValue)
        local rowCount = readRowCount(section, rootKey)
        if rowCount ~= nil then
            return rowCount
        end

        defaultValue = normalizeRowCount(defaultValue)
        if defaultValue == nil then
            return nil
        end

        local entry = bindEntry(getTableRootSection(section, rootKey), TABLE_ROW_COUNT_KEY, defaultValue)
        if not entry then
            return nil
        end

        requestSave()
        metrics.count("entry_gets")
        local getOk, value = callMethod(entry, "get")
        if not getOk then
            return nil
        end

        rowCount = normalizeRowCount(value)
        if rowCount ~= nil then
            metrics.count("row_count_hits")
        end
        return rowCount
    end

    local function writeRowCount(section, rootKey, rowCount)
        rowCount = normalizeRowCount(rowCount)
        if rowCount == nil then
            return false, false
        end

        local entry = backend.getEntry(getTableRootSection(section, rootKey), TABLE_ROW_COUNT_KEY)
        if entry then
            metrics.count("entry_gets")
            local getOk, current = callMethod(entry, "get")
            if getOk and normalizeRowCount(current) == rowCount then
                return true, false
            end
            metrics.count("entry_sets")
            local setOk = callMethod(entry, "set", rowCount)
            if setOk then
                metrics.count("table_cell_changes")
            end
            return setOk, setOk
        end

        entry = bindEntry(getTableRootSection(section, rootKey), TABLE_ROW_COUNT_KEY, rowCount)
        return entry ~= nil, entry ~= nil
    end

    local function saveRawConfig()
        local startedMs = nowMs()
        metrics.count("saves")
        callMethod(rawConfig, "save")
        metrics.count("save_time_ms", nowMs() - startedMs)
    end

    requestSave = function()
        if saveBatchDepth > 0 then
            savePending = true
            return
        end
        saveRawConfig()
    end

    function backend.beginSaveBatch()
        saveBatchDepth = saveBatchDepth + 1
    end

    function backend.endSaveBatch()
        if saveBatchDepth <= 0 then
            return false
        end
        saveBatchDepth = saveBatchDepth - 1
        if saveBatchDepth == 0 and savePending then
            savePending = false
            saveRawConfig()
            return true
        end
        return false
    end

    function backend.getEntry(section, key)
        metrics.count("get_entries")
        local cacheKey = makeCacheKey(section, key)
        local cached = pathEntryCache[cacheKey]
        if cached ~= nil then
            if cached then
                metrics.count("get_entry_hits")
            else
                metrics.count("get_entry_misses")
            end
            return cached or nil
        end

        local sectionEntries = entryIndex[section]
        local entry = sectionEntries and sectionEntries[key] or nil
        if entry then
            pathEntryCache[cacheKey] = entry
            metrics.count("get_entry_hits")
            return entry
        end

        pathEntryCache[cacheKey] = false
        metrics.count("get_entry_misses")
        return nil
    end

    function backend.ensure(section, key, value)
        local entry = backend.getEntry(section, key)
        if entry then
            return true
        end

        if not isFlatValue(value) then
            return false
        end

        entry = bindEntry(section, key, value)
        if not entry then
            return false
        end

        requestSave()
        return true
    end

    function backend.read(section, key)
        metrics.count("reads")
        local entry = backend.getEntry(section, key)
        if entry then
            metrics.count("entry_gets")
            local getOk, value = callMethod(entry, "get")
            if getOk then
                return value
            end
            return nil
        end
        return nil
    end

    function backend.readBound(section, key, value)
        metrics.count("reads")
        local entry = backend.getEntry(section, key)
        if not entry then
            if not isFlatValue(value) then
                return nil
            end
            entry = bindEntry(section, key, value)
            if not entry then
                return nil
            end
            requestSave()
        end

        metrics.count("entry_gets")
        local getOk, boundValue = callMethod(entry, "get")
        if getOk then
            return boundValue
        end
        return nil
    end

    function backend.write(section, key, value)
        local startedMs = nowMs()
        if not isFlatValue(value) then
            metrics.count("write_scalar_time_ms", nowMs() - startedMs)
            return false
        end

        local entry = backend.getEntry(section, key)
        if entry then
            metrics.count("entry_sets")
            local setOk = callMethod(entry, "set", value)
            if setOk then
                requestSave()
                metrics.count("write_scalar_time_ms", nowMs() - startedMs)
                return true
            end
        end
        metrics.count("write_scalar_time_ms", nowMs() - startedMs)
        return false
    end

    function backend.readTable(section, node)
        metrics.count("read_tables")
        if type(node) ~= "table" or node.type ~= "table" then
            return nil
        end

        local rootKey = getTableRootKey(node)
        if type(section) ~= "string" or type(rootKey) ~= "string" then
            return nil
        end

        local rowRoots = getTableRowRoots(node)
        if #rowRoots == 0 then
            return nil
        end

        local rowCount = readBoundRowCount(section, rootKey, node.defaultRows or 0)
        if rowCount ~= nil then
            local rows = {}
            for index = 1, rowCount do
                local rowSection = getTableRootSection(section, rootKey) .. "." .. tostring(index)
                local row = {}
                for _, root in ipairs(rowRoots) do
                    local key = root._storageKey or root.alias
                    local entry = key and backend.getEntry(rowSection, key) or nil
                    if not entry then
                        entry = bindEntry(rowSection, key, root.default)
                        if entry then
                            requestSave()
                        end
                    end
                    if entry then
                        metrics.count("entry_gets")
                        local getOk, value = callMethod(entry, "get")
                        if getOk and value ~= nil then
                            row[root.alias] = value
                        end
                    end
                end
                rows[index] = row
            end
            return rows
        end

        local prefix = section .. "." .. rootKey .. "."
        local rows = {}
        local maxRowIndex = 0
        local found = false

        metrics.count("fallback_scans")
        for entrySection, sectionEntries in pairs(entryIndex) do
            metrics.count("fallback_sections_scanned")
            if startsWith(entrySection, prefix) and type(sectionEntries) == "table" then
                local rowText = string.sub(entrySection, #prefix + 1)
                local rowIndex = tonumber(rowText)
                if rowIndex ~= nil and rowIndex >= 1 and rowIndex == math.floor(rowIndex)
                    and string.find(rowText, "%.") == nil then
                    local row = rows[rowIndex] or {}
                    local rowFound = false
                    for _, root in ipairs(rowRoots) do
                        local key = root._storageKey or root.alias
                        local entry = key and sectionEntries[key] or nil
                        if entry then
                            metrics.count("entry_gets")
                            local getOk, value = callMethod(entry, "get")
                            if getOk and value ~= nil then
                                row[root.alias] = value
                                rowFound = true
                            end
                        end
                    end
                    if rowFound then
                        rows[rowIndex] = row
                        if rowIndex > maxRowIndex then
                            maxRowIndex = rowIndex
                        end
                        found = true
                    end
                end
            end
        end

        if not found then
            return nil
        end

        for index = 1, maxRowIndex do
            rows[index] = rows[index] or {}
        end
        local rowCountOk, rowCountChanged = writeRowCount(section, rootKey, #rows)
        if rowCountOk and rowCountChanged then
            requestSave()
        end
        return rows
    end

    function backend.writeTableCells(section, rootKey, cells, rowCount)
        local startedMs = nowMs()
        metrics.count("write_tables")
        if type(section) ~= "string" or section == "" or type(rootKey) ~= "string" or rootKey == ""
            or type(cells) ~= "table" or type(readField(rawConfig, "bind")) ~= "function" then
            metrics.count("write_table_time_ms", nowMs() - startedMs)
            return false
        end
        metrics.count("table_cells", #cells)

        local wanted = {}
        local changed = false
        local normalizedRowCount = normalizeRowCount(rowCount)

        local rowCountStartedMs = nowMs()
        if normalizedRowCount == nil then
            normalizedRowCount = 0
            local prefix = getTableRootSection(section, rootKey) .. "."
            for _, cell in ipairs(cells) do
                if type(cell.section) == "string" and startsWith(cell.section, prefix) then
                    local rowText = string.sub(cell.section, #prefix + 1)
                    local rowIndex = tonumber(rowText)
                    if rowIndex ~= nil and rowIndex >= 1 and rowIndex == math.floor(rowIndex)
                        and string.find(rowText, "%.") == nil and rowIndex > normalizedRowCount then
                        normalizedRowCount = rowIndex
                    end
                end
            end
        end

        local rowCountOk, rowCountChanged = writeRowCount(section, rootKey, normalizedRowCount)
        if not rowCountOk then
            metrics.count("write_table_row_count_time_ms", nowMs() - rowCountStartedMs)
            metrics.count("write_table_time_ms", nowMs() - startedMs)
            return false
        end
        metrics.count("write_table_row_count_time_ms", nowMs() - rowCountStartedMs)
        changed = rowCountChanged

        local cellsStartedMs = nowMs()
        for _, cell in ipairs(cells) do
            local cellSection = cell.section
            local key = cell.key
            local value = cell.value
            if type(cellSection) ~= "string" or cellSection == "" or type(key) ~= "string" or key == ""
                or not isFlatValue(value) then
                metrics.count("write_table_cells_time_ms", nowMs() - cellsStartedMs)
                metrics.count("write_table_time_ms", nowMs() - startedMs)
                return false
            end

            wanted[cellSection] = wanted[cellSection] or {}
            wanted[cellSection][key] = true

            local entry = backend.getEntry(cellSection, key)
            if entry then
                metrics.count("entry_gets")
                local getOk, current = callMethod(entry, "get")
                if not getOk or current ~= value then
                    metrics.count("entry_sets")
                    local setOk = callMethod(entry, "set", value)
                    if not setOk then
                        return false
                    end
                    metrics.count("table_cell_changes")
                    changed = true
                end
            else
                entry = bindEntry(cellSection, key, value)
                if not entry then
                    metrics.count("write_table_cells_time_ms", nowMs() - cellsStartedMs)
                    metrics.count("write_table_time_ms", nowMs() - startedMs)
                    return false
                end
                metrics.count("table_cell_changes")
                changed = true
            end
        end
        metrics.count("write_table_cells_time_ms", nowMs() - cellsStartedMs)

        local prefix = section .. "." .. rootKey .. "."
        local pruneStartedMs = nowMs()
        metrics.count("prune_scans")
        for entrySection, sectionEntries in pairs(entryIndex) do
            if startsWith(entrySection, prefix) and type(sectionEntries) == "table" then
                metrics.count("prune_sections_scanned")
                for key, entry in pairs(sectionEntries) do
                    metrics.count("prune_entries_scanned")
                    if not (wanted[entrySection] and wanted[entrySection][key]) then
                        metrics.count("entry_gets")
                        local getOk, current = callMethod(entry, "get")
                        if getOk and current ~= nil then
                            metrics.count("entry_sets")
                            local setOk = callMethod(entry, "set", nil)
                            if not setOk then
                                metrics.count("write_table_prune_time_ms", nowMs() - pruneStartedMs)
                                metrics.count("write_table_time_ms", nowMs() - startedMs)
                                return false
                            end
                            metrics.count("table_cell_changes")
                            changed = true
                        end
                    end
                end
            end
        end
        metrics.count("write_table_prune_time_ms", nowMs() - pruneStartedMs)

        if changed then
            requestSave()
        end
        metrics.count("write_table_time_ms", nowMs() - startedMs)
        return true
    end

    function backend.clear(section, key)
        local entry = backend.getEntry(section, key)
        if entry then
            metrics.count("entry_sets")
            local setOk = callMethod(entry, "set", nil)
            if setOk then
                requestSave()
                return true
            end
        end
        return false
    end

    function backend.beginDiagnosticScope()
        return metrics.beginScope()
    end

    function backend.printDiagnosticScope(label, phase, scope)
        local sections = 0
        local entriesCount = 0
        for _, sectionEntries in pairs(entryIndex) do
            sections = sections + 1
            if type(sectionEntries) == "table" then
                for _ in pairs(sectionEntries) do
                    entriesCount = entriesCount + 1
                end
            end
        end

        metrics.printScope(label, phase, scope, entriesCount, sections)
    end

    backend.rawConfig = rawConfig
    backendCache[rawConfig] = backend
    return backend
end

return {
    create = create,
}
