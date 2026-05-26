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
    create = function(ownerId, key, opts)
        return currentRunCache.create(getCurrentRun, ownerId, key, opts)
    end,
}

service.persistent = {
    read = function(cacheStore, ownerId, key, defaultValue)
        return persistentCache.read(cacheStore, ownerId, key, defaultValue)
    end,
    create = function(cacheStore, ownerId, key, opts)
        return persistentCache.create(cacheStore, ownerId, key, opts)
    end,
}

local dataCache = import('core/cache/adapters/data_cache.lua', nil, {
    logging = deps.logging,
    phaseGate = deps.phaseGate,
    service = service,
})
service.data = dataCache

return {
    service = service,
    data = dataCache,
}
