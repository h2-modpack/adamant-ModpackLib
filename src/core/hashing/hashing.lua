local deps = ...

local storageApi = deps.storage
local hashing = {}

function hashing.getRoots(storage)
    return storageApi.getRoots(storage)
end

function hashing.valuesEqual(node, a, b)
    return storageApi.valuesEqual(node, a, b)
end

function hashing.toHash(node, value)
    return storageApi.toHash(node, value)
end

function hashing.fromHash(node, str)
    return storageApi.fromHash(node, str)
end

function hashing.isHashTokenValid(node, str)
    return storageApi.isHashTokenValid(node, str)
end

return {
    framework = hashing,
}
