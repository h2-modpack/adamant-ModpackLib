local deps = ...

local logging = deps.logging
local persistentCache = {}

local function validateOwnerId(ownerId)
    if type(ownerId) ~= "string" or ownerId == "" then
        logging.violate("cache.invalid_args", "cache ownerId must be a non-empty string")
    end
end

local function validateKey(context, key)
    if type(key) ~= "string" or key == "" then
        logging.violate("cache.invalid_args", "%s key must be a non-empty string", context)
    end
end

local function validateScalar(context, value, optional)
    if value == nil and optional then
        return
    end
    local valueType = type(value)
    if valueType ~= "boolean" and valueType ~= "number" and valueType ~= "string" then
        logging.violate("cache.invalid_value", "%s value must be a boolean, number, or string", context)
    end
end

local function getBackingKey(ownerId, key)
    return tostring(#ownerId) .. ":" .. ownerId .. ":" .. key
end

function persistentCache.read(cacheStore, ownerId, key, defaultValue)
    validateOwnerId(ownerId)
    validateKey("cache.persistent.read", key)
    validateScalar("cache.persistent.read default", defaultValue, true)

    local value = cacheStore.read(getBackingKey(ownerId, key))
    if value == nil then
        return defaultValue
    end
    return value
end

function persistentCache.write(cacheStore, ownerId, key, value)
    validateOwnerId(ownerId)
    validateKey("cache.persistent.write", key)
    validateScalar("cache.persistent.write", value, false)

    return cacheStore.write(getBackingKey(ownerId, key), value)
end

function persistentCache.clear(cacheStore, ownerId, key)
    validateOwnerId(ownerId)
    validateKey("cache.persistent.clear", key)

    return cacheStore.clear(getBackingKey(ownerId, key))
end

function persistentCache.has(cacheStore, ownerId, key)
    validateOwnerId(ownerId)
    validateKey("cache.persistent.has", key)

    return cacheStore.has(getBackingKey(ownerId, key))
end

function persistentCache.snapshotRef(cacheStore, ownerId, key, defaultValue)
    validateOwnerId(ownerId)
    validateKey("cache.persistent.snapshotRef", key)
    validateScalar("cache.persistent.snapshotRef default", defaultValue, true)

    local backingKey = getBackingKey(ownerId, key)
    local snapshot = cacheStore.read(backingKey)
    if snapshot == nil then
        snapshot = defaultValue
    end

    local ref = {}

    ref.get = function()
        return snapshot
    end
    ref.set = function(selfOrValue, maybeValue)
        local value = maybeValue
        if value == nil and selfOrValue ~= ref then
            value = selfOrValue
        end
        validateScalar("cache.persistent.snapshotRef.set", value, false)
        local ok = cacheStore.write(backingKey, value)
        if ok then
            snapshot = value
        end
        return ok
    end
    ref.clear = function()
        local ok = cacheStore.clear(backingKey)
        snapshot = defaultValue
        return ok
    end
    ref.has = function()
        return cacheStore.has(backingKey)
    end
    ref.refresh = function()
        local value = cacheStore.read(backingKey)
        if value == nil then
            snapshot = defaultValue
        else
            snapshot = value
        end
        return snapshot
    end

    return ref
end

return persistentCache
