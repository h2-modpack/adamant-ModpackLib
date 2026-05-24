local deps = ...

local gameDeps = deps.gameDeps

local snapshotObject = import('core/cache/snapshot_object.lua')
local currentRunCache = import('core/cache/current_run_cache.lua', nil, {
    logging = deps.logging,
    snapshotObject = snapshotObject,
})
local persistentCache = import('core/cache/persistent_cache.lua', nil, {
    logging = deps.logging,
    snapshotObject = snapshotObject,
})
local sharedCache = import('core/cache/shared_cache.lua', nil, {
    logging = deps.logging,
    snapshotObject = snapshotObject,
    values = deps.values,
    sharedRegistry = deps.cacheRegistry.shared,
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
    create = function(ownerId, key, opts)
        return currentRunCache.create(getCurrentRun, ownerId, key, opts)
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
    create = function(cacheStore, ownerId, key, opts)
        return persistentCache.create(cacheStore, ownerId, key, opts)
    end,
}

service.shared = {
    stagePublication = function(record, host, id, opts)
        return sharedCache.stagePublication(record, host, id, opts)
    end,
    install = function(ownerId, publications)
        return sharedCache.install(ownerId, publications)
    end,
    read = function(id, fallback)
        return sharedCache.read(id, fallback)
    end,
    write = function(ownerId, ownerToken, id, value)
        return sharedCache.write(ownerId, ownerToken, id, value)
    end,
    clear = function(ownerId, ownerToken, id)
        return sharedCache.clear(ownerId, ownerToken, id)
    end,
    createOwner = function(record, host, id, opts)
        return sharedCache.createOwner(record, host, id, opts)
    end,
    createReader = function(id, opts)
        return sharedCache.createReader(id, opts)
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
