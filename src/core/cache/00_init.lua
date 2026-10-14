local deps = ...

local currentRunCache = import('core/cache/current_run_cache.lua', nil, {
    logging = deps.logging,
    getCurrentRun = deps.gameDeps.cache.CurrentRun,
})

local data = import('core/cache/data_cache.lua', nil, {
    logging = deps.logging,
    currentRunCache = currentRunCache,
})

return {
    data = data,
}
