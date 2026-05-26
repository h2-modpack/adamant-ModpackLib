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

function persistentCache.create(cacheStore, ownerId, key, opts)
    validateOwnerId(ownerId)
    validateKey("cache.persistent.ref", key)
    if opts ~= nil and type(opts) ~= "table" then
        logging.violate("cache.invalid_args", "cache.persistent.ref opts must be a table when provided")
    end
    opts = opts or {}
    validateScalar("cache.persistent.ref default", opts.default, true)

    local function load()
        local value = cacheStore.read(getBackingKey(ownerId, key))
        if value == nil then
            return opts.default
        end
        return value
    end

    local snapshot = load()
    local ref = {}
    ref.get = function()
        return snapshot
    end
    ref.set = function(_, value)
        validateScalar("cache.persistent.ref.set", value, false)
        local ok = cacheStore.write(getBackingKey(ownerId, key), value)
        if ok then
            snapshot = value
        end
        return ok
    end
    ref.clear = function()
        local ok = cacheStore.clear(getBackingKey(ownerId, key))
        if ok then
            snapshot = opts.default
        end
        return ok
    end
    return ref
end

return persistentCache
