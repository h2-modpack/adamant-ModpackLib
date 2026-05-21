local deps = ...

local logging = deps.logging
local hostState = deps.hostState
local service = deps.service
local author = {}

local function getHostState(host, context)
    local state = hostState.get(host)
    if not state then
        logging.violate("cache.invalid_args", "%s: expected managed module host state", context)
    end
    return state
end

local function getHostOwnerId(host, context)
    getHostState(host, context)
    return host.getHostId()
end

local function getPersistentCacheState(host, context)
    local state = getHostState(host, context)
    local cacheStore = state.cacheStore
    if not (cacheStore and type(cacheStore.read) == "function" and type(cacheStore.write) == "function"
        and type(cacheStore.clear) == "function" and type(cacheStore.has) == "function") then
        logging.violate("cache.invalid_args", "%s: expected managed persistent cache store", context)
    end
    return host.getHostId(), cacheStore
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
    }
end

return author
