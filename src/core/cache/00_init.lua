local deps = ...

local gameDeps = deps.gameDeps

local currentRunCache = import('core/cache/current_run_cache.lua', nil, {
    logging = deps.logging,
    getCurrentRun = function()
        return gameDeps.cache.CurrentRun()
    end,
})

local data = import('core/cache/adapters/data_cache.lua', nil, {
    logging = deps.logging,
    currentRunCache = currentRunCache,
})

return {
    data = data,
}
