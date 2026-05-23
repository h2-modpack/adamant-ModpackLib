local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local service = deps.service
local author = {}

local function getHostRecord(host, context)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("cache.invalid_args", "%s: expected managed module host record", context)
    end
    return record
end

local function getHostOwnerId(host, context)
    getHostRecord(host, context)
    return host.getHostId()
end

local function requireRegistrationOpen(host, context)
    local record = getHostRecord(host, context)
    if record.activated == true or record.activating == true then
        logging.violate("cache.invalid_args", "%s cannot publish after activation begins", context)
    end
    return record
end

local function getPersistentCacheState(host, context)
    local record = getHostRecord(host, context)
    local cacheStore = record.cacheStore
    if not (cacheStore and type(cacheStore.read) == "function" and type(cacheStore.write) == "function"
        and type(cacheStore.clear) == "function" and type(cacheStore.has) == "function") then
        logging.violate("cache.invalid_args", "%s: expected managed persistent cache store", context)
    end
    return host.getHostId(), cacheStore
end

local function getSharedWriteState(host, context)
    local record = getHostRecord(host, context)
    local publications = record.sharedCachePublications
    local ownerToken = publications and publications.ownerToken or nil
    if ownerToken == nil then
        logging.violate("cache.shared_not_owner", "%s requires an activated shared cache publication", context)
    end
    return host.getHostId(), ownerToken
end

function author.create(host)
    return {
        currentRun = {
            get = function(key, factory)
                local ownerId = getHostOwnerId(host, "host.cache.currentRun.get")
                return service.currentRun.get(ownerId, key, factory)
            end,
            peek = function(key)
                local ownerId = getHostOwnerId(host, "host.cache.currentRun.peek")
                return service.currentRun.peek(ownerId, key)
            end,
            clear = function(key)
                local ownerId = getHostOwnerId(host, "host.cache.currentRun.clear")
                return service.currentRun.clear(ownerId, key)
            end,
        },
        persistent = {
            read = function(key, defaultValue)
                local ownerId, cacheStore = getPersistentCacheState(host, "host.cache.persistent.read")
                return service.persistent.read(cacheStore, ownerId, key, defaultValue)
            end,
            write = function(key, value)
                local ownerId, cacheStore = getPersistentCacheState(host, "host.cache.persistent.write")
                return service.persistent.write(cacheStore, ownerId, key, value)
            end,
            clear = function(key)
                local ownerId, cacheStore = getPersistentCacheState(host, "host.cache.persistent.clear")
                return service.persistent.clear(cacheStore, ownerId, key)
            end,
            has = function(key)
                local ownerId, cacheStore = getPersistentCacheState(host, "host.cache.persistent.has")
                return service.persistent.has(cacheStore, ownerId, key)
            end,
        },
        shared = {
            publish = function(id, opts)
                return service.shared.stagePublication(
                    requireRegistrationOpen(host, "host.cache.shared.publish"),
                    host,
                    id,
                    opts)
            end,
            read = function(id, fallback)
                getHostRecord(host, "host.cache.shared.read")
                return service.shared.read(id, fallback)
            end,
            write = function(id, value)
                local ownerId, ownerToken = getSharedWriteState(host, "host.cache.shared.write")
                return service.shared.write(ownerId, ownerToken, id, value)
            end,
            clear = function(id)
                local ownerId, ownerToken = getSharedWriteState(host, "host.cache.shared.clear")
                return service.shared.clear(ownerId, ownerToken, id)
            end,
        },
    }
end

return author
