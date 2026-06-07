local deps = ...

local storageApi = deps.storage
local StorageTypes = storageApi.types
local hashing = {}

function hashing.getRoots(storage)
    return storageApi.getRoots(storage)
end

function hashing.valuesEqual(node, a, b)
    return storageApi.valuesEqual(node, a, b)
end

function hashing.toHash(node, value)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.toHash(node, value)
end

function hashing.fromHash(node, str)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.fromHash(node, str)
end

function hashing.isHashTokenValid(node, str)
    return storageApi.isHashTokenValid(node, str)
end

return {
    framework = hashing,
}
