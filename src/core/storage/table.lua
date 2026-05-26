local deps = ...

local logging = deps.logging
local storageInternal = deps.storage
local StorageTypes = deps.types
local values = deps.values

local function ClampRowCount(node, count)
    count = math.floor(tonumber(count) or 0)
    if count < 0 then count = 0 end
    if node.minRows ~= nil and count < node.minRows then count = node.minRows end
    if node.maxRows ~= nil and count > node.maxRows then count = node.maxRows end
    return count
end

local function GetRowAliasNodes(node)
    return node and node.row and storageInternal.getAliases(node.row) or {}
end

local function GetRowRootNodes(node)
    return node and node.row and storageInternal.getRoots(node.row) or {}
end

local function CreateDefaultTableRow(node)
    local row = {}
    for _, root in ipairs(GetRowRootNodes(node)) do
        row[root.alias] = values.deepCopy(root.default)
    end
    return row
end

local NormalizeTableRow
local NormalizeTableValue

local function readRowRootValue(root, row, normalizedRoot)
    local value = row[root.alias]
    if value == nil then
        return values.deepCopy(root.default)
    end
    if normalizedRoot == true then
        return value
    end
    return storageInternal.NormalizeStorageValue(root, value)
end

local function writeRowRootValue(root, row, value)
    row[root.alias] = storageInternal.NormalizeStorageValue(root, value)
    return true
end

local function unknownRowAlias(node, rowAlias)
    logging.violate(
        "storage.unknown_table_row_alias",
        "table storage '%s': unknown row alias '%s'",
        tostring(node.alias),
        tostring(rowAlias)
    )
end

local function createRowBackend(node, normalizedRoot)
    local currentRow
    return {
        bindRow = function(row)
            currentRow = row
        end,
        readRoot = function(root)
            return readRowRootValue(root, currentRow, normalizedRoot)
        end,
        writeRoot = function(root, rootValue)
            return writeRowRootValue(root, currentRow, rootValue)
        end,
        onUnknownRead = function(rowAlias)
            unknownRowAlias(node, rowAlias)
        end,
        onUnknownWrite = function(rowAlias)
            unknownRowAlias(node, rowAlias)
        end,
    }
end

local function validateTableReceiver(node, handle, receiver, methodName)
    if receiver ~= handle then
        logging.violate(
            "storage.invalid_table_handle_args",
            "table storage '%s': invalid receiver for %s",
            tostring(node.alias),
            tostring(methodName)
        )
    end
end

local function validateRowIndex(node, rowIndex, methodName)
    if type(rowIndex) ~= "number" then
        logging.violate(
            "storage.invalid_table_handle_args",
            "table storage '%s': %s expects numeric rowIndex",
            tostring(node.alias),
            tostring(methodName)
        )
    end
end

local function validateRowAlias(node, alias, methodName)
    if type(alias) ~= "string" or alias == "" then
        logging.violate(
            "storage.invalid_table_handle_args",
            "table storage '%s': %s expects non-empty row alias",
            tostring(node.alias),
            tostring(methodName)
        )
    end
end

local function getAliasNodeOrError(node, aliasNodes, alias)
    local aliasNode = aliasNodes[alias]
    if not aliasNode then
        unknownRowAlias(node, alias)
    end
    return aliasNode
end

local function PrepareTableNode(node, prefix)
    if type(node.row) ~= "table" then
        return
    end

    for index, rowNode in ipairs(node.row) do
        local rowPrefix = prefix .. " row[" .. index .. "]"
        if type(rowNode) == "table" then
            if rowNode.type == "table" then
                logging.violate("storage.invalid_table_row", "%s: nested table storage is not supported", rowPrefix)
            end
            if rowNode.persist ~= nil then
                logging.violate(
                    "storage.invalid_table_row",
                    "%s: row storage cannot declare persist; table root owns persistence",
                    rowPrefix
                )
            end
            if rowNode.hash ~= nil then
                logging.violate("storage.invalid_table_row", "%s: row storage cannot declare hash; table root owns hashing", rowPrefix)
            end
            if rowNode.mode ~= nil then
                logging.violate("storage.invalid_table_row", "%s: row storage cannot declare mode; table root owns mode", rowPrefix)
            end
        end
    end

    storageInternal.validate(node.row, prefix .. " row")

    node.minRows = ClampRowCount({ minRows = 0 }, node.minRows or 0)
    node.maxRows = node.maxRows ~= nil and ClampRowCount({ minRows = 0 }, node.maxRows) or nil
    if node.maxRows ~= nil and node.minRows > node.maxRows then
        node.minRows = node.maxRows
    end
    node.defaultRows = ClampRowCount(node, node.defaultRows or node.minRows or 0)
    node.default = NormalizeTableValue(node, nil)
    node._tableDefaultPrepared = true
end

NormalizeTableRow = function(node, rowValue)
    local row = CreateDefaultTableRow(node)
    if type(rowValue) ~= "table" then
        return row
    end
    local aliasNodes = GetRowAliasNodes(node)

    for _, root in ipairs(GetRowRootNodes(node)) do
        if rowValue[root.alias] ~= nil then
            row[root.alias] = storageInternal.NormalizeStorageValue(root, rowValue[root.alias])
        end
    end

    local rowBackend = createRowBackend(node, false)
    rowBackend.bindRow(row)

    for alias, value in pairs(rowValue) do
        if aliasNodes[alias] ~= nil then
            storageInternal.writeAlias(aliasNodes, rowBackend, alias, value)
        end
    end

    return row
end

NormalizeTableValue = function(node, value)
    local rows = {}
    local source = type(value) == "table" and value or nil
    local count = source and #source or node.defaultRows or 0
    count = ClampRowCount(node, count)

    for index = 1, count do
        rows[index] = NormalizeTableRow(node, source and source[index] or nil)
    end
    return rows
end

local function EncodeLengthPrefixed(value)
    value = tostring(value or "")
    return tostring(#value) .. ":" .. value
end

local function DecodeLengthPrefixed(str, pos)
    local lenText, nextPos = string.match(str, "^(%d+):()", pos)
    if not lenText then
        return nil, nil
    end
    local len = tonumber(lenText) or 0
    local valueStart = nextPos
    local valueEnd = valueStart + len - 1
    if valueEnd > #str then
        return nil, nil
    end
    return string.sub(str, valueStart, valueEnd), valueEnd + 1
end

local function SerializeTableValue(node, value)
    local rows = NormalizeTableValue(node, value)
    local parts = { tostring(#rows) .. ":" }
    for _, row in ipairs(rows) do
        for _, root in ipairs(GetRowRootNodes(node)) do
            local storageType = StorageTypes[root.type]
            local encoded = storageType.toHash(root, row[root.alias])
            parts[#parts + 1] = EncodeLengthPrefixed(encoded)
        end
    end
    return table.concat(parts)
end

local function DeserializeTableValue(node, str)
    if type(str) ~= "string" then
        return NormalizeTableValue(node, nil)
    end

    local countText, pos = string.match(str, "^(%d+):()")
    if not countText then
        return NormalizeTableValue(node, nil)
    end

    local rows = {}
    local count = ClampRowCount(node, tonumber(countText) or 0)
    local roots = GetRowRootNodes(node)
    for rowIndex = 1, count do
        local row = {}
        for _, root in ipairs(roots) do
            local encoded
            encoded, pos = DecodeLengthPrefixed(str, pos)
            if encoded == nil then
                return NormalizeTableValue(node, nil)
            end
            local storageType = StorageTypes[root.type]
            row[root.alias] = storageType.fromHash(root, encoded)
        end
        rows[rowIndex] = NormalizeTableRow(node, row)
    end
    return NormalizeTableValue(node, rows)
end

local function IsSerializedTableValue(node, str)
    if type(str) ~= "string" then
        return false
    end

    local countText, pos = string.match(str, "^(%d+):()")
    if not countText then
        return false
    end

    local count = tonumber(countText) or 0
    if ClampRowCount(node, count) ~= count then
        return false
    end

    local roots = GetRowRootNodes(node)
    for _ = 1, count do
        for _, root in ipairs(roots) do
            local encoded
            encoded, pos = DecodeLengthPrefixed(str, pos)
            if encoded == nil then
                return false
            end
            if not storageInternal.isHashTokenValid(root, encoded) then
                return false
            end
        end
    end

    return pos == #str + 1
end

local function CreateTableHandle(node, opts)
    opts = opts or {}
    local aliasNodes = GetRowAliasNodes(node)
    local rowOwners = {}
    local rowControlIds = {}
    local rowFields = {}

    local function readRows()
        local rows = opts.readRoot(node)
        if opts.normalizedRoot == true then
            return type(rows) == "table" and rows or node.default
        end
        return NormalizeTableValue(node, rows)
    end

    local function copyRows()
        if opts.normalizedRoot == true then
            return values.deepCopy(readRows())
        end
        return readRows()
    end

    local function writeRows(rows)
        if opts.writeRoot == nil then
            logging.violate("storage.readonly_table_handle", "table storage handle is read-only")
        end
        return opts.writeRoot(node, NormalizeTableValue(node, rows))
    end

    local function getRowCount(rows)
        return ClampRowCount(node, type(rows) == "table" and #rows or 0)
    end

    local function readRow(rows, rowIndex)
        rowIndex = math.floor(tonumber(rowIndex) or 0)
        if rowIndex < 1 or rowIndex > getRowCount(rows) then
            return nil, rowIndex
        end
        return rows[rowIndex], rowIndex
    end

    local rowBackend = createRowBackend(node, opts.normalizedRoot == true)

    local function readRowAlias(row, alias)
        rowBackend.bindRow(row)
        return storageInternal.readAlias(aliasNodes, rowBackend, alias)
    end

    local function writeRowAlias(row, alias, value)
        rowBackend.bindRow(row)
        return storageInternal.writeAlias(aliasNodes, rowBackend, alias, value)
    end

    local handle = {}

    local function getRowAliasNodeOrNil(alias)
        local aliasNode = aliasNodes[alias]
        if not aliasNode then
            unknownRowAlias(node, alias)
            return nil
        end
        return aliasNode
    end

    local function clearRowStructureCaches()
        rowOwners = {}
        rowControlIds = {}
        rowFields = {}
    end

    local function getRowFieldControlId(rowIndex, alias)
        rowIndex = math.floor(tonumber(rowIndex) or 0)
        local rowIds = rowControlIds[rowIndex]
        if not rowIds then
            rowIds = {}
            rowControlIds[rowIndex] = rowIds
        end

        local id = rowIds[alias]
        if not id then
            id = tostring(node.alias) .. ":" .. tostring(rowIndex) .. ":" .. tostring(alias)
            rowIds[alias] = id
        end
        return id
    end

    local function writeStructuralRows(rows)
        local changed = writeRows(rows) ~= false
        if changed then
            clearRowStructureCaches()
        end
        return changed
    end

    local function getRowOwnerForIndex(rowIndex)
        rowIndex = math.floor(tonumber(rowIndex) or 0)
        local cached = rowOwners[rowIndex]
        if cached then
            return cached
        end

        local rowOwner = {
            read = function(alias)
                validateRowAlias(node, alias, "rowOwner.read")
                local row = readRow(readRows(), rowIndex)
                if not row then
                    return nil
                end
                return readRowAlias(row, alias)
            end,
            getAliasSchema = function(alias)
                validateRowAlias(node, alias, "rowOwner.getAliasSchema")
                return aliasNodes[alias]
            end,
            getFieldControlId = function(alias)
                validateRowAlias(node, alias, "rowOwner.getFieldControlId")
                return getRowFieldControlId(rowIndex, alias)
            end,
        }

        if opts.writeRoot ~= nil then
            rowOwner.write = function(alias, value)
                validateRowAlias(node, alias, "rowOwner.write")
                local rows = copyRows()
                local row = readRow(rows, rowIndex)
                if not row then
                    return false
                end
                local changed = writeRowAlias(row, alias, value)
                if changed then
                    writeRows(rows)
                end
                return changed
            end

            rowOwner.reset = function(alias)
                validateRowAlias(node, alias, "rowOwner.reset")
                local rows = copyRows()
                local row = readRow(rows, rowIndex)
                if not row then
                    return false
                end
                local aliasNode = getAliasNodeOrError(node, aliasNodes, alias)
                local changed = writeRowAlias(row, alias, values.deepCopy(aliasNode.default))
                if changed then
                    writeRows(rows)
                end
                return changed
            end
        end

        rowOwners[rowIndex] = rowOwner
        return rowOwner
    end

    function handle.count(self)
        validateTableReceiver(node, handle, self, "count")
        return getRowCount(readRows())
    end

    function handle.read(self, rowIndex, alias)
        validateTableReceiver(node, handle, self, "read")
        validateRowIndex(node, rowIndex, "read")
        validateRowAlias(node, alias, "read")
        local row = readRow(readRows(), rowIndex)
        if not row then
            return nil
        end
        return readRowAlias(row, alias)
    end

    function handle.snapshot(self, rowIndex)
        validateTableReceiver(node, handle, self, "snapshot")
        validateRowIndex(node, rowIndex, "snapshot")
        local row = readRow(readRows(), rowIndex)
        return row and values.deepCopy(row) or nil
    end

    function handle.snapshots(self)
        validateTableReceiver(node, handle, self, "snapshots")
        return values.deepCopy(readRows())
    end

    function handle.get(self, rowIndex, alias)
        validateTableReceiver(node, handle, self, "get")
        validateRowIndex(node, rowIndex, "get")
        validateRowAlias(node, alias, "get")
        local aliasNode = getRowAliasNodeOrNil(alias)
        if not aliasNode then
            return nil
        end

        rowIndex = math.floor(tonumber(rowIndex) or 0)
        local rowCache = rowFields[rowIndex]
        if not rowCache then
            rowCache = {}
            rowFields[rowIndex] = rowCache
        end

        local cached = rowCache[alias]
        if cached then
            return cached
        end

        local field = storageInternal.field.createKnown(getRowOwnerForIndex(rowIndex), alias, aliasNode, "table.get")
        rowCache[alias] = field
        return field
    end

    if opts.writeRoot ~= nil then
        function handle.write(self, rowIndex, alias, value)
            validateTableReceiver(node, handle, self, "write")
            validateRowIndex(node, rowIndex, "write")
            validateRowAlias(node, alias, "write")
            local rows = copyRows()
            local row = readRow(rows, rowIndex)
            if not row then
                return false
            end
            local changed = writeRowAlias(row, alias, value)
            if changed then
                writeRows(rows)
            end
            return changed
        end

        function handle.reset(self, rowIndex, alias)
            validateTableReceiver(node, handle, self, "reset")
            validateRowIndex(node, rowIndex, "reset")
            validateRowAlias(node, alias, "reset")
            local rows = copyRows()
            local row = readRow(rows, rowIndex)
            if not row then
                return false
            end
            local aliasNode = getAliasNodeOrError(node, aliasNodes, alias)
            local changed = writeRowAlias(row, alias, values.deepCopy(aliasNode.default))
            if changed then
                writeRows(rows)
            end
            return changed
        end

        function handle.append(self, rowValues)
            validateTableReceiver(node, handle, self, "append")
            local rows = copyRows()
            if node.maxRows ~= nil and #rows >= node.maxRows then
                return false
            end
            rows[#rows + 1] = NormalizeTableRow(node, rowValues)
            return writeStructuralRows(rows)
        end

        function handle.insert(self, rowIndex, rowValues)
            validateTableReceiver(node, handle, self, "insert")
            validateRowIndex(node, rowIndex, "insert")
            local rows = copyRows()
            if node.maxRows ~= nil and #rows >= node.maxRows then
                return false
            end
            rowIndex = math.floor(tonumber(rowIndex) or (#rows + 1))
            if rowIndex < 1 then rowIndex = 1 end
            if rowIndex > #rows + 1 then rowIndex = #rows + 1 end
            table.insert(rows, rowIndex, NormalizeTableRow(node, rowValues))
            return writeStructuralRows(rows)
        end

        function handle.remove(self, rowIndex)
            validateTableReceiver(node, handle, self, "remove")
            validateRowIndex(node, rowIndex, "remove")
            local rows = copyRows()
            rowIndex = math.floor(tonumber(rowIndex) or 0)
            if rowIndex < 1 or rowIndex > #rows then
                return false
            end
            table.remove(rows, rowIndex)
            return writeStructuralRows(rows)
        end

        function handle.clear(self)
            validateTableReceiver(node, handle, self, "clear")
            return writeStructuralRows({})
        end
    end

    return handle
end

return {
    PrepareTableNode = PrepareTableNode,
    NormalizeTableRow = NormalizeTableRow,
    NormalizeTableValue = NormalizeTableValue,
    SerializeTableValue = SerializeTableValue,
    DeserializeTableValue = DeserializeTableValue,
    IsSerializedTableValue = IsSerializedTableValue,
    CreateTableHandle = CreateTableHandle,
}
