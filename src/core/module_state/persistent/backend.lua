local deps = ...

local chalk = deps.chalk
local backendCache = setmetatable({}, { __mode = "k" })
local TABLE_ROW_COUNT_KEY = "_RowCount"

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

local function shouldDebugAlias(section, key)
    return rawget(_G, "AdamantEnableToggleDebug") == true
        and section == "config"
        and (key == "Enabled" or key == "DebugMode" or key == "AdamantFramework_PackRestoreSnapshot")
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

        local bindOk, entry = callMethod(rawConfig, "bind", section, key, value, "")
        if not bindOk or not entry then
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
            return nil
        end

        local getOk, value = callMethod(entry, "get")
        if not getOk then
            return nil
        end
        return normalizeRowCount(value)
    end

    local function writeRowCount(section, rootKey, rowCount)
        rowCount = normalizeRowCount(rowCount)
        if rowCount == nil then
            return false, false
        end

        local entry = backend.getEntry(getTableRootSection(section, rootKey), TABLE_ROW_COUNT_KEY)
        if entry then
            local getOk, current = callMethod(entry, "get")
            if getOk and normalizeRowCount(current) == rowCount then
                return true, false
            end
            local setOk = callMethod(entry, "set", rowCount)
            return setOk, setOk
        end

        entry = bindEntry(getTableRootSection(section, rootKey), TABLE_ROW_COUNT_KEY, rowCount)
        return entry ~= nil, entry ~= nil
    end

    local function saveRawConfig()
        callMethod(rawConfig, "save")
    end

    local function requestSave()
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
        local cacheKey = makeCacheKey(section, key)
        local cached = pathEntryCache[cacheKey]
        if cached ~= nil then
            return cached or nil
        end

        local sectionEntries = entryIndex[section]
        local entry = sectionEntries and sectionEntries[key] or nil
        if entry then
            pathEntryCache[cacheKey] = entry
            return entry
        end

        pathEntryCache[cacheKey] = false
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
        local entry = backend.getEntry(section, key)
        if entry then
            local getOk, value = callMethod(entry, "get")
            if shouldDebugAlias(section, key) then
                print(string.format("[lib-debug] backend read section=%s key=%s entry=true get_ok=%s value=%s",
                    tostring(section), tostring(key), tostring(getOk), tostring(value)))
            end
            if getOk then
                return value
            end
            return nil
        end
        if shouldDebugAlias(section, key) then
            print(string.format("[lib-debug] backend read section=%s key=%s entry=false value=nil",
                tostring(section), tostring(key)))
        end
        return nil
    end

    function backend.write(section, key, value)
        if not isFlatValue(value) then
            return false
        end

        local entry = backend.getEntry(section, key)
        if entry then
            local setOk = callMethod(entry, "set", value)
            if setOk then
                requestSave()
                return true
            end
        end
        return false
    end

    function backend.readTable(section, node)
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

        local rowCount = readRowCount(section, rootKey)
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
                    end
                    if entry then
                        local getOk, value = callMethod(entry, "get")
                        if getOk and value ~= nil then
                            row[root.alias] = value
                        end
                    end
                end
                rows[index] = row
            end
            if rawget(_G, "AdamantEnableToggleDebug") == true then
                print(string.format(
                    "[lib-debug] backend readTable root=%s found=true source=row_count row_count=%s row_roots=%s",
                    tostring(rootKey),
                    tostring(rowCount),
                    tostring(#rowRoots)))
            end
            return rows
        end

        local prefix = section .. "." .. rootKey .. "."
        local rows = {}
        local maxRowIndex = 0
        local found = false
        local matchedSections = 0
        local matchedRows = 0

        for entrySection, sectionEntries in pairs(entryIndex) do
            if startsWith(entrySection, prefix) and type(sectionEntries) == "table" then
                local rowText = string.sub(entrySection, #prefix + 1)
                local rowIndex = tonumber(rowText)
                if rowIndex ~= nil and rowIndex >= 1 and rowIndex == math.floor(rowIndex)
                    and string.find(rowText, "%.") == nil then
                    matchedSections = matchedSections + 1
                    local row = rows[rowIndex] or {}
                    local rowFound = false
                    for _, root in ipairs(rowRoots) do
                        local key = root._storageKey or root.alias
                        local entry = key and sectionEntries[key] or nil
                        if entry then
                            local getOk, value = callMethod(entry, "get")
                            if getOk and value ~= nil then
                                row[root.alias] = value
                                rowFound = true
                            end
                        end
                    end
                    if rowFound then
                        matchedRows = matchedRows + 1
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
            if rawget(_G, "AdamantEnableToggleDebug") == true then
                print(string.format(
                    "[lib-debug] backend readTable root=%s found=false matched_sections=%s matched_rows=%s row_roots=%s",
                    tostring(rootKey),
                    tostring(matchedSections),
                    tostring(matchedRows),
                    tostring(#rowRoots)))
            end
            return nil
        end

        for index = 1, maxRowIndex do
            rows[index] = rows[index] or {}
        end
        local rowCountOk, rowCountChanged = writeRowCount(section, rootKey, #rows)
        if rowCountOk and rowCountChanged then
            requestSave()
        end
        if rawget(_G, "AdamantEnableToggleDebug") == true then
            print(string.format(
                "[lib-debug] backend readTable root=%s found=true matched_sections=%s matched_rows=%s max_row_index=%s row_count=%s row_roots=%s",
                tostring(rootKey),
                tostring(matchedSections),
                tostring(matchedRows),
                tostring(maxRowIndex),
                tostring(#rows),
                tostring(#rowRoots)))
        end
        return rows
    end

    function backend.writeTableCells(section, rootKey, cells, rowCount)
        if type(section) ~= "string" or section == "" or type(rootKey) ~= "string" or rootKey == ""
            or type(cells) ~= "table" or type(readField(rawConfig, "bind")) ~= "function" then
            return false
        end

        local wanted = {}
        local changed = false
        local normalizedRowCount = normalizeRowCount(rowCount)

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
            return false
        end
        changed = rowCountChanged

        for _, cell in ipairs(cells) do
            local cellSection = cell.section
            local key = cell.key
            local value = cell.value
            if type(cellSection) ~= "string" or cellSection == "" or type(key) ~= "string" or key == ""
                or not isFlatValue(value) then
                return false
            end

            wanted[cellSection] = wanted[cellSection] or {}
            wanted[cellSection][key] = true

            local entry = backend.getEntry(cellSection, key)
            if entry then
                local getOk, current = callMethod(entry, "get")
                if not getOk or current ~= value then
                    local setOk = callMethod(entry, "set", value)
                    if not setOk then
                        return false
                    end
                    changed = true
                end
            else
                entry = bindEntry(cellSection, key, value)
                if not entry then
                    return false
                end
                changed = true
            end
        end

        local prefix = section .. "." .. rootKey .. "."
        for entrySection, sectionEntries in pairs(entryIndex) do
            if startsWith(entrySection, prefix) and type(sectionEntries) == "table" then
                for key, entry in pairs(sectionEntries) do
                    if not (wanted[entrySection] and wanted[entrySection][key]) then
                        local getOk, current = callMethod(entry, "get")
                        if getOk and current ~= nil then
                            local setOk = callMethod(entry, "set", nil)
                            if not setOk then
                                return false
                            end
                            changed = true
                        end
                    end
                end
            end
        end

        if changed then
            requestSave()
        end
        return true
    end

    function backend.clear(section, key)
        local entry = backend.getEntry(section, key)
        if entry then
            local setOk = callMethod(entry, "set", nil)
            if setOk then
                requestSave()
                return true
            end
        end
        return false
    end

    backend.rawConfig = rawConfig
    backendCache[rawConfig] = backend
    return backend
end

return {
    create = create,
}
