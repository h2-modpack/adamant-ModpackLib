local deps = ...

local logging = deps.logging
local currentRunCache = {}

local ROOT_KEY = "_AdamantModpackLibCache"

local function tableIsEmpty(value)
    return next(value) == nil
end

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

local function validateFactory(context, factory)
    if factory ~= nil and type(factory) ~= "function" then
        logging.violate("cache.invalid_factory", "%s factory must be a function", context)
    end
end

local function getOwnerBucket(currentRun, ownerId, create)
    local root = rawget(currentRun, ROOT_KEY)
    if root == nil and create then
        root = {}
        rawset(currentRun, ROOT_KEY, root)
    end
    if type(root) ~= "table" then
        if create then
            logging.violate("cache.invalid_bucket", "cache.currentRun root bucket is not a table")
        end
        return nil
    end

    local ownerBucket = root[ownerId]
    if ownerBucket == nil and create then
        ownerBucket = {}
        root[ownerId] = ownerBucket
    end
    if type(ownerBucket) ~= "table" then
        if create then
            logging.violate("cache.invalid_bucket", "cache.currentRun owner bucket is not a table")
        end
        return nil
    end

    return ownerBucket, root
end

local function getFromCurrentRun(currentRun, ownerId, key, factory)
    local ownerBucket = getOwnerBucket(currentRun, ownerId, true)
    local state = ownerBucket[key]
    if state == nil then
        if factory ~= nil then
            state = factory()
        end
        if state == nil then
            state = {}
        end
        if type(state) ~= "table" then
            logging.violate("cache.invalid_factory", "cache.currentRun factory must return a table")
        end
        ownerBucket[key] = state
    end
    if type(state) ~= "table" then
        logging.violate("cache.invalid_bucket", "cache.currentRun cache bucket is not a table")
    end
    return state
end

local function clearFromCurrentRun(currentRun, ownerId, key)
    local ownerBucket, root = getOwnerBucket(currentRun, ownerId, false)
    if not ownerBucket or ownerBucket[key] == nil then
        return false
    end
    ownerBucket[key] = nil
    if tableIsEmpty(ownerBucket) then
        root[ownerId] = nil
        if tableIsEmpty(root) then
            rawset(currentRun, ROOT_KEY, nil)
        end
    end
    return true
end

currentRunCache.create = function(getCurrentRun, ownerId, key, opts)
    validateOwnerId(ownerId)
    validateKey("cache.currentRun.create", key)
    if opts ~= nil and type(opts) ~= "table" then
        logging.violate("cache.invalid_args", "cache.currentRun.create opts must be a table when provided")
    end
    opts = opts or {}
    validateFactory("cache.currentRun.create", opts.factory)

    local lastRun = nil
    local bucket = nil

    local function syncRun()
        local currentRun = getCurrentRun()
        if currentRun ~= lastRun then
            lastRun = currentRun
            bucket = nil
        end
        return currentRun
    end

    return {
        get = function()
            local currentRun = syncRun()
            if currentRun == nil then
                return nil
            end
            if bucket == nil then
                bucket = getFromCurrentRun(currentRun, ownerId, key, opts.factory)
            end
            return bucket
        end,
        clear = function()
            local currentRun = syncRun()
            if currentRun == nil then
                bucket = nil
                return false
            end
            local ok = clearFromCurrentRun(currentRun, ownerId, key)
            bucket = nil
            return ok
        end,
    }
end

return currentRunCache
