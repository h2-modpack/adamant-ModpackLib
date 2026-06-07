local deps = ...

local storageService = deps.storage
local StorageTypes = storageService.types
local hashing = {}

---@param storage StorageSchema
---@return StorageNode[]
function hashing.getRoots(storage)
    return storageService.getRoots(storage)
end

---@param node StorageNode|PackedBitNode|nil
---@param a any
---@param b any
---@return boolean
function hashing.valuesEqual(node, a, b)
    return storageService.valuesEqual(node, a, b)
end

---@param node StorageNode|PackedBitNode
---@param value any
---@return string|nil
function hashing.toHash(node, value)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.toHash(node, value)
end

---@param node StorageNode|PackedBitNode
---@param str string
---@return any
function hashing.fromHash(node, str)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.fromHash(node, str)
end

---@param node StorageNode|PackedBitNode
---@param str string|nil
---@return boolean
function hashing.isHashTokenValid(node, str)
    return storageService.isHashTokenValid(node, str)
end

return {
    framework = hashing,
}
