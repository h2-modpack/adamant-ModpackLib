local deps = ...

local gameDeps = deps.gameDeps

local currentRunCache = import('core/cache/current_run_cache.lua', nil, {
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

local dataCache = import('core/cache/adapters/data_cache.lua', nil, {
    logging = deps.logging,
    service = service,
})
service.data = dataCache

return {
    service = service,
    data = dataCache,
}
