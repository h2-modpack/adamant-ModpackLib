local deps = ...

local backendMetrics = deps.metrics
local TABLE_ROW_COUNT_KEY = "_RowCount"

local function nowMs()
    return os.clock() * 1000
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function startsWith(value, prefix)
    return type(value) == "string" and string.sub(value, 1, #prefix) == prefix
end

local function isFlatValue(value)
    local valueType = type(value)
    return valueType == "boolean" or valueType == "number" or valueType == "string"
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

local function getTableRootKey(node)
    return type(node) == "table" and (node._storageKey or node.alias) or nil
end

local function getTableRootSection(section, rootKey)
    return section .. "." .. rootKey
end

local function getTableRowRoots(node)
    local rowSchema = type(node) == "table" and type(node.row) == "table" and node.row or nil
    if not rowSchema then
        return {}
    end
    return rawget(rowSchema, "_rootNodes") or {}
end

local function splitPath(path)
    local section, key = string.match(path, "^(.*)%.([^%.]+)$")
    return section, key
end

local function unescapeString(value)
    value = string.gsub(value, "\\n", "\n")
    value = string.gsub(value, '\\"', '"')
    value = string.gsub(value, "\\\\", "\\")
    return value
end

local function parseValue(rawValue)
    rawValue = trim(rawValue)
    if rawValue == "" then
        return ""
    end

    local first = string.sub(rawValue, 1, 1)
    local last = string.sub(rawValue, -1)
    if first == '"' and last == '"' and #rawValue >= 2 then
        return unescapeString(string.sub(rawValue, 2, -2))
    end

    local lower = string.lower(rawValue)
    if lower == "true" then
        return true
    elseif lower == "false" then
        return false
    end

    local numberValue = tonumber(rawValue)
    if numberValue ~= nil then
        return numberValue
    end

    return rawValue
end

local function escapeString(value)
    value = tostring(value or "")
    value = string.gsub(value, "\\", "\\\\")
    value = string.gsub(value, '"', '\\"')
    value = string.gsub(value, "\n", "\\n")
    return value
end

local function formatValue(value)
    if type(value) == "boolean" then
        return value and "true" or "false"
    elseif type(value) == "number" then
        return tostring(value)
    end
    return '"' .. escapeString(value) .. '"'
end

local function getSettingType(value)
    if type(value) == "boolean" then
        return "Boolean"
    elseif type(value) == "number" then
        return "double"
    end
    return "string"
end

local function sortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function createEntry(value, defaultValue)
    return {
        value = value,
        default = defaultValue,
    }
end

local function create(opts)
    local path = type(opts) == "table" and opts.path or nil
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local metrics = backendMetrics.create("native")
    local sections = {}
    local saveBatchDepth = 0
    local savePending = false
    local backend = {}

    local function getSection(section)
        local sectionEntries = sections[section]
        if not sectionEntries then
            sectionEntries = {}
            sections[section] = sectionEntries
        end
        return sectionEntries
    end

    local function getEntry(section, key)
        metrics.count("get_entries")
        local sectionEntries = sections[section]
        local entry = sectionEntries and sectionEntries[key] or nil
        if entry then
            metrics.count("get_entry_hits")
        else
            metrics.count("get_entry_misses")
        end
        return entry
    end

    local function setEntry(section, key, value, defaultValue)
        if type(section) ~= "string" or section == "" or type(key) ~= "string" or key == ""
            or not isFlatValue(value) then
            return false
        end
        local sectionEntries = getSection(section)
        local entry = sectionEntries[key]
        if not entry then
            sectionEntries[key] = createEntry(value, defaultValue)
        else
            entry.value = value
            if defaultValue ~= nil then
                entry.default = defaultValue
            end
        end
        return true
    end

    local function removeEntry(section, key)
        local sectionEntries = sections[section]
        if sectionEntries then
            sectionEntries[key] = nil
        end
    end

    local function markDirty()
        savePending = true
    end

    local function loadFile()
        local startedMs = nowMs()
        local file = io.open(path, "r")
        if not file then
            metrics.count("parse_time_ms", nowMs() - startedMs)
            return
        end

        local currentSection = "config"
        for line in file:lines() do
            local section = string.match(line, "^%s*%[([^%]]+)%]%s*$")
            if section then
                currentSection = trim(section)
            elseif not string.match(line, "^%s*[#;]") then
                local key, rawValue = string.match(line, "^%s*([^=]-)%s*=%s*(.-)%s*$")
                key = key and trim(key) or nil
                if key and key ~= "" then
                    setEntry(currentSection, key, parseValue(rawValue), nil)
                end
            end
        end
        file:close()
        metrics.count("parse_time_ms", nowMs() - startedMs)
    end

    local function saveFile()
        local startedMs = nowMs()
        local file = io.open(path, "w")
        if not file then
            metrics.count("save_time_ms", nowMs() - startedMs)
            return
        end

        file:write("## Settings file was created by plugin adamant-ModpackLib native backend\n\n")
        for _, section in ipairs(sortedKeys(sections)) do
            local sectionEntries = sections[section]
            local keys = sortedKeys(sectionEntries)
            if #keys > 0 then
                file:write("[", section, "]\n\n")
                for _, key in ipairs(keys) do
                    local entry = sectionEntries[key]
                    local value = entry.value
                    local defaultValue = entry.default
                    if defaultValue == nil then
                        defaultValue = value
                    end
                    file:write("# Setting type: ", getSettingType(value), "\n")
                    file:write("# Default value: ", formatValue(defaultValue), "\n")
                    file:write(key, " = ", formatValue(value), "\n\n")
                end
            end
        end
        file:close()
        metrics.count("saves")
        metrics.count("save_time_ms", nowMs() - startedMs)
    end

    local function requestSave()
        if saveBatchDepth > 0 then
            savePending = true
            return
        end
        savePending = false
        saveFile()
    end

    loadFile()

    function backend.reload()
        sections = {}
        loadFile()
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
            saveFile()
            return true
        end
        return false
    end

    function backend.getEntry(section, key)
        return getEntry(section, key)
    end

    function backend.read(section, key)
        metrics.count("reads")
        local entry = getEntry(section, key)
        if entry then
            metrics.count("entry_gets")
            return entry.value
        end
        return nil
    end

    function backend.readBound(section, key, defaultValue)
        metrics.count("reads")
        local entry = getEntry(section, key)
        if entry then
            metrics.count("entry_gets")
            if defaultValue ~= nil then
                entry.default = defaultValue
            end
            return entry.value
        end
        if not isFlatValue(defaultValue) then
            return nil
        end
        setEntry(section, key, defaultValue, defaultValue)
        markDirty()
        metrics.count("entry_sets")
        return defaultValue
    end

    function backend.ensure(section, key, value)
        local entry = getEntry(section, key)
        if entry then
            return true
        end
        if not isFlatValue(value) then
            return false
        end
        setEntry(section, key, value, value)
        requestSave()
        metrics.count("entry_sets")
        return true
    end

    function backend.write(section, key, value)
        local startedMs = nowMs()
        if not isFlatValue(value) then
            metrics.count("write_scalar_time_ms", nowMs() - startedMs)
            return false
        end
        local entry = getEntry(section, key)
        if entry and entry.value == value then
            metrics.count("write_scalar_time_ms", nowMs() - startedMs)
            return true
        end
        setEntry(section, key, value, entry and entry.default or value)
        requestSave()
        metrics.count("entry_sets")
        metrics.count("write_scalar_time_ms", nowMs() - startedMs)
        return true
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

        local rootSection = getTableRootSection(section, rootKey)
        local rowCountEntry = getEntry(rootSection, TABLE_ROW_COUNT_KEY)
        local rowCount = rowCountEntry and normalizeRowCount(rowCountEntry.value) or nil
        if rowCount == nil then
            metrics.count("row_count_misses")
            metrics.count("fallback_scans")
            local prefix = rootSection .. "."
            rowCount = 0
            for entrySection in pairs(sections) do
                metrics.count("fallback_sections_scanned")
                if startsWith(entrySection, prefix) then
                    local rowText = string.sub(entrySection, #prefix + 1)
                    local rowIndex = tonumber(rowText)
                    if rowIndex ~= nil and rowIndex >= 1 and rowIndex == math.floor(rowIndex)
                        and string.find(rowText, "%.") == nil and rowIndex > rowCount then
                        rowCount = rowIndex
                    end
                end
            end
            if rowCount == 0 then
                rowCount = node.defaultRows or 0
            end
            setEntry(rootSection, TABLE_ROW_COUNT_KEY, rowCount, node.defaultRows or 0)
            markDirty()
            metrics.count("entry_sets")
        else
            metrics.count("row_count_hits")
            if node.defaultRows ~= nil then
                rowCountEntry.default = node.defaultRows
            end
        end

        local rows = {}
        for index = 1, rowCount do
            local rowSection = rootSection .. "." .. tostring(index)
            local row = {}
            for _, root in ipairs(rowRoots) do
                local key = root._storageKey or root.alias
                local entry = key and getEntry(rowSection, key) or nil
                if entry then
                    metrics.count("entry_gets")
                    entry.default = root.default
                    row[root.alias] = entry.value
                elseif key and isFlatValue(root.default) then
                    setEntry(rowSection, key, root.default, root.default)
                    markDirty()
                    metrics.count("entry_sets")
                    row[root.alias] = root.default
                end
            end
            rows[index] = row
        end
        return rows
    end

    function backend.writeTableCells(section, rootKey, cells, rowCount)
        local startedMs = nowMs()
        metrics.count("write_tables")
        if type(section) ~= "string" or section == "" or type(rootKey) ~= "string" or rootKey == ""
            or type(cells) ~= "table" then
            metrics.count("write_table_time_ms", nowMs() - startedMs)
            return false
        end
        metrics.count("table_cells", #cells)

        local rootSection = getTableRootSection(section, rootKey)
        local normalizedRowCount = normalizeRowCount(rowCount) or 0
        local changed = false
        local rowCountStartedMs = nowMs()
        local rowCountEntry = getEntry(rootSection, TABLE_ROW_COUNT_KEY)
        if not rowCountEntry or normalizeRowCount(rowCountEntry.value) ~= normalizedRowCount then
            setEntry(rootSection, TABLE_ROW_COUNT_KEY, normalizedRowCount, normalizedRowCount)
            metrics.count("table_cell_changes")
            changed = true
        end
        metrics.count("write_table_row_count_time_ms", nowMs() - rowCountStartedMs)

        local wanted = {}
        local cellsStartedMs = nowMs()
        for _, cell in ipairs(cells) do
            if type(cell.section) ~= "string" or type(cell.key) ~= "string" or not isFlatValue(cell.value) then
                metrics.count("write_table_cells_time_ms", nowMs() - cellsStartedMs)
                metrics.count("write_table_time_ms", nowMs() - startedMs)
                return false
            end
            wanted[cell.section] = wanted[cell.section] or {}
            wanted[cell.section][cell.key] = true
            local entry = getEntry(cell.section, cell.key)
            if not entry or entry.value ~= cell.value then
                setEntry(cell.section, cell.key, cell.value, cell.value)
                metrics.count("table_cell_changes")
                changed = true
            elseif entry then
                entry.default = cell.value
            end
        end
        metrics.count("write_table_cells_time_ms", nowMs() - cellsStartedMs)

        local prefix = rootSection .. "."
        local pruneStartedMs = nowMs()
        metrics.count("prune_scans")
        for entrySection, sectionEntries in pairs(sections) do
            if startsWith(entrySection, prefix) and type(sectionEntries) == "table" then
                local rowText = string.sub(entrySection, #prefix + 1)
                local rowIndex = tonumber(rowText)
                if rowIndex ~= nil and rowIndex >= 1 and rowIndex == math.floor(rowIndex)
                    and string.find(rowText, "%.") == nil then
                    metrics.count("prune_sections_scanned")
                    for key in pairs(sectionEntries) do
                        metrics.count("prune_entries_scanned")
                        if rowIndex > normalizedRowCount or not (wanted[entrySection] and wanted[entrySection][key]) then
                            sectionEntries[key] = nil
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
        if getEntry(section, key) then
            removeEntry(section, key)
            requestSave()
            metrics.count("entry_sets")
            return true
        end
        return false
    end

    function backend.beginDiagnosticScope()
        return metrics.beginScope()
    end

    function backend.printDiagnosticScope(label, phase, scope)
        local sectionCount = 0
        local entryCount = 0
        for _, sectionEntries in pairs(sections) do
            sectionCount = sectionCount + 1
            for _ in pairs(sectionEntries) do
                entryCount = entryCount + 1
            end
        end

        metrics.printScope(label, phase, scope, entryCount, sectionCount)
    end

    return backend
end

return {
    create = create,
}
