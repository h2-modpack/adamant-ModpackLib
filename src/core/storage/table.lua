local deps = ...

local logging = deps.logging
local values = deps.values
local nodeOps = deps.nodeOps
local aliasAccess = deps.aliasAccess
local storageField = deps.field

local function NonNegativeCount(count)
    count = math.floor(tonumber(count) or 0)
    if count < 0 then count = 0 end
    return count
end

local function ClampRowCount(node, count)
    count = NonNegativeCount(count)
    if node.minRows ~= nil and count < node.minRows then count = node.minRows end
    if node.maxRows ~= nil and count > node.maxRows then count = node.maxRows end
    return count
end

-- Row schemas are prepared by schema.validate before the table root is prepared.
local function GetRowAliasNodes(node)
    return node.row._aliasNodes
end

local function GetRowRootNodes(node)
    return node.row._rootNodes
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
    return nodeOps.normalize(root, value)
end

local function writeRowRootValue(root, row, value)
    row[root.alias] = nodeOps.normalize(root, value)
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

-- Contact-point checks for row declarations; runs before schema.validate prepares node.row.
local function ValidateRowDeclarations(node, prefix)
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
end

-- Normalizes row-count axes and the default value once node.row is prepared.
local function PrepareTableNode(node)
    node.minRows = NonNegativeCount(node.minRows or 0)
    node.maxRows = node.maxRows ~= nil and NonNegativeCount(node.maxRows) or nil
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

    for _, root in ipairs(GetRowRootNodes(node)) do
        if rowValue[root.alias] ~= nil then
            row[root.alias] = nodeOps.normalize(root, rowValue[root.alias])
        end
    end

    -- Packed child values apply on top of their (already normalized) packed roots.
    local aliasNodes = GetRowAliasNodes(node)
    local rowBackend = createRowBackend(node, false)
    rowBackend.bindRow(row)
    for alias, value in pairs(rowValue) do
        local aliasNode = aliasNodes[alias]
        if aliasNode ~= nil and aliasNode._isBitAlias then
            aliasAccess.writeAlias(aliasNodes, rowBackend, alias, value)
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

local function ForEachNormalizedTableCell(node, value, visitor)
    local rows = NormalizeTableValue(node, value)
    for rowIndex, row in ipairs(rows) do
        for _, root in ipairs(GetRowRootNodes(node)) do
            visitor(rowIndex, root, row[root.alias], row)
        end
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
    local parts = {}
    local rows = ForEachNormalizedTableCell(node, value, function(_, root, cellValue)
        parts[#parts + 1] = EncodeLengthPrefixed(nodeOps.toHash(root, cellValue))
    end)
    table.insert(parts, 1, tostring(#rows) .. ":")
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
            row[root.alias] = nodeOps.fromHash(root, encoded)
        end
        rows[rowIndex] = NormalizeTableRow(node, row)
    end
    return rows
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
            if not nodeOps.isHashTokenValid(root, encoded) then
                return false
            end
        end
    end

    return pos == #str + 1
end

local function CreateTableHandle(node, opts)
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
        return aliasAccess.readAlias(aliasNodes, rowBackend, alias)
    end

    local function writeRowAlias(row, alias, value)
        rowBackend.bindRow(row)
        return aliasAccess.writeAlias(aliasNodes, rowBackend, alias, value)
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

    local function readRowCell(rowIndex, alias)
        local row = readRow(readRows(), rowIndex)
        if not row then
            return nil
        end
        return readRowAlias(row, alias)
    end

    -- Writes one cell (or resets it to its row-schema default) and stores the rows on change.
    local function updateRowCell(rowIndex, alias, value, reset)
        local rows = copyRows()
        local row = readRow(rows, rowIndex)
        if not row then
            return false
        end
        if reset then
            local aliasNode = getRowAliasNodeOrNil(alias)
            if not aliasNode then
                return false
            end
            value = values.deepCopy(aliasNode.default)
        end
        local changed = writeRowAlias(row, alias, value)
        if changed then
            writeRows(rows)
        end
        return changed
    end

    -- Row owners back StorageFields created by handle.get; fields pass their own (known)
    -- alias or one checked by StorageField.readAlias/writeAlias.
    local function getRowOwnerForIndex(rowIndex)
        rowIndex = math.floor(tonumber(rowIndex) or 0)
        local cached = rowOwners[rowIndex]
        if cached then
            return cached
        end

        local rowOwner = {
            read = function(alias)
                return readRowCell(rowIndex, alias)
            end,
            getAliasSchema = function(alias)
                return aliasNodes[alias]
            end,
            getFieldControlId = function(alias)
                return getRowFieldControlId(rowIndex, alias)
            end,
        }

        if opts.writeRoot ~= nil then
            rowOwner.write = function(alias, value)
                return updateRowCell(rowIndex, alias, value, false)
            end

            rowOwner.reset = function(alias)
                return updateRowCell(rowIndex, alias, nil, true)
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
        return readRowCell(rowIndex, alias)
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

        local field = storageField.create(getRowOwnerForIndex(rowIndex), alias, aliasNode, "table.get")
        rowCache[alias] = field
        return field
    end

    if opts.writeRoot ~= nil then
        function handle.write(self, rowIndex, alias, value)
            validateTableReceiver(node, handle, self, "write")
            validateRowIndex(node, rowIndex, "write")
            validateRowAlias(node, alias, "write")
            return updateRowCell(rowIndex, alias, value, false)
        end

        function handle.reset(self, rowIndex, alias)
            validateTableReceiver(node, handle, self, "reset")
            validateRowIndex(node, rowIndex, "reset")
            validateRowAlias(node, alias, "reset")
            return updateRowCell(rowIndex, alias, nil, true)
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

-- Storage type descriptor for `table` roots; storage/00_init.lua registers it in the type map.
local tableType = {
    validate = function(node, prefix)
        if node.default ~= nil and node._tableDefaultPrepared ~= true then
            logging.violate("storage.invalid_default", "%s: table roots do not support default; use defaultRows", prefix)
        end
        if node.minRows ~= nil and (type(node.minRows) ~= "number" or node.minRows < 0) then
            logging.violate("storage.invalid_axis_type", "%s: table minRows must be a non-negative number", prefix)
        end
        if node.maxRows ~= nil and (type(node.maxRows) ~= "number" or node.maxRows < 0) then
            logging.violate("storage.invalid_axis_type", "%s: table maxRows must be a non-negative number", prefix)
        end
        if node.defaultRows ~= nil and (type(node.defaultRows) ~= "number" or node.defaultRows < 0) then
            logging.violate("storage.invalid_axis_type", "%s: table defaultRows must be a non-negative number", prefix)
        end
        if type(node.minRows) == "number" and type(node.maxRows) == "number" and node.minRows > node.maxRows then
            logging.violate("storage.invalid_axis_type", "%s: table minRows cannot exceed maxRows", prefix)
        end
        if type(node.row) ~= "table" or #node.row == 0 then
            logging.violate("storage.invalid_table_row", "%s: table row must be a non-empty storage schema", prefix)
        end
    end,
    normalize = NormalizeTableValue,
    equals = function(node, a, b)
        return values.deepEqual(NormalizeTableValue(node, a), NormalizeTableValue(node, b))
    end,
    toHash = SerializeTableValue,
    fromHash = DeserializeTableValue,
    isHashTokenValid = IsSerializedTableValue,
}

return {
    tableType = tableType,
    ValidateRowDeclarations = ValidateRowDeclarations,
    PrepareTableNode = PrepareTableNode,
    ForEachNormalizedTableCell = ForEachNormalizedTableCell,
    CreateTableHandle = CreateTableHandle,
}
