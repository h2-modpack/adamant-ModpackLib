local deps = ...

local values = deps.values
local StorageTypes = deps.types

-- Value operations over prepared storage nodes, dispatched by node type. Nodes reaching
-- these functions were prepared by schema.validate, so their type is always registered.
local nodeOps = {}

---@param key any
---@return boolean
function nodeOps.isInternalField(key)
    return type(key) == "string" and string.sub(key, 1, 1) == "_"
end

---@param node AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode
function nodeOps.normalize(node, value)
    return StorageTypes[node.type].normalize(node, value)
end

---@param node AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode
---@return boolean
function nodeOps.valuesEqual(node, a, b)
    local equals = StorageTypes[node.type].equals
    if equals ~= nil then
        return equals(node, a, b)
    end
    return values.deepEqual(a, b)
end

---@param node AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode
---@return string
function nodeOps.toHash(node, value)
    return StorageTypes[node.type].toHash(node, value)
end

---@param node AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode
---@param str string
function nodeOps.fromHash(node, str)
    return StorageTypes[node.type].fromHash(node, str)
end

---@param node AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode
---@return boolean
function nodeOps.isHashTokenValid(node, str)
    return StorageTypes[node.type].isHashTokenValid(node, str)
end

return nodeOps
