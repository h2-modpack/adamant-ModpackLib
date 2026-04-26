local internal = AdamantModpackLib_Internal
local storageInternal = internal.storage
local StorageTypes = storageInternal.types

public.hashing = public.hashing or {}
local hashingApi = public.hashing

--- Returns the prepared persistent root nodes for a validated storage schema.
---@param storage StorageSchema Validated storage schema.
---@return StorageNode[] roots Prepared list of persistent root storage nodes.
function hashingApi.getRoots(storage)
    return storageInternal.getRoots(storage)
end

--- Returns the prepared alias map for a validated storage schema.
---@param storage StorageSchema Validated storage schema.
---@return table<string, StorageNode|PackedBitNode> aliases Map from storage alias to prepared storage node.
function hashingApi.getAliases(storage)
    return storageInternal.getAliases(storage)
end

--- Compares two values using storage-type equality when available, falling back to deep equality.
---@param node StorageNode|PackedBitNode|nil Storage node whose type-specific equality should be used.
---@param a any First value to compare.
---@param b any Second value to compare.
---@return boolean equal True when the two values are considered equivalent for the storage node.
function hashingApi.valuesEqual(node, a, b)
    return storageInternal.valuesEqual(node, a, b)
end

--- Returns the packed width contributed by a storage node, when the node type supports packing.
---@param node StorageNode|PackedBitNode Storage node to inspect.
---@return number|nil width Packed width in bits, or nil when the node is not packable.
function hashingApi.getPackWidth(node)
    if type(node) ~= "table" then return nil end
    local storageType = StorageTypes[node.type]
    if storageType and storageType.packWidth then
        return storageType.packWidth(node)
    end
    return nil
end

--- Encodes a storage value into its hash string form using the node's storage type.
---@param node StorageNode|PackedBitNode Storage node whose type-specific hash encoder should be used.
---@param value any Value to encode.
---@return string|nil encoded Encoded hash value, or nil when the node type is unknown.
function hashingApi.toHash(node, value)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.toHash(node, value)
end

--- Decodes a storage value from its hash string form using the node's storage type.
---@param node StorageNode|PackedBitNode Storage node whose type-specific hash decoder should be used.
---@param str string Encoded hash value.
---@return any decoded Decoded value, or nil when the node type is unknown.
function hashingApi.fromHash(node, str)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.fromHash(node, str)
end

--- Reads a bitfield value from a packed integer using an offset and width.
---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@return number
function hashingApi.readPackedBits(packed, offset, width)
    return storageInternal.readPackedBits(packed, offset, width)
end

--- Writes a bitfield value into a packed integer using an offset and width.
---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@param value number|nil
---@return number
function hashingApi.writePackedBits(packed, offset, width, value)
    return storageInternal.writePackedBits(packed, offset, width, value)
end
