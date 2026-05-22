local deps = ...

local gameDeps = deps.gameDeps

local currentRunCache = import('core/cache/current_run_cache.lua', nil, {
    logging = deps.logging,
})
local persistentCache = import('core/cache/persistent_cache.lua', nil, {
    logging = deps.logging,
})

local service = {}

local function getCurrentRun()
    return gameDeps.cache.CurrentRun()
end

service.currentRun = {
    get = function(ownerId, key, factory)
        return currentRunCache.get(getCurrentRun(), ownerId, key, factory)
    end,
    peek = function(ownerId, key)
        return currentRunCache.peek(getCurrentRun(), ownerId, key)
    end,
    clear = function(ownerId, key)
        return currentRunCache.clear(getCurrentRun(), ownerId, key)
    end,
}

service.persistent = {
    read = function(cacheStore, ownerId, key, defaultValue)
        return persistentCache.read(cacheStore, ownerId, key, defaultValue)
    end,
    write = function(cacheStore, ownerId, key, value)
        return persistentCache.write(cacheStore, ownerId, key, value)
    end,
    clear = function(cacheStore, ownerId, key)
        return persistentCache.clear(cacheStore, ownerId, key)
    end,
    has = function(cacheStore, ownerId, key)
        return persistentCache.has(cacheStore, ownerId, key)
    end,
}

local author = import('core/cache/adapters/author_cache.lua', nil, {
    logging = deps.logging,
    hostRegistry = deps.hostRegistry,
    service = service,
})

return {
    service = service,
    author = author,
}
