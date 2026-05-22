local persistentCacheStore = {}

local CACHE_SECTION = "cache"
local FALLBACK_ROOT_KEY = "_AdamantModpackLibPersistentCache"

local function getFallbackRoot(config, create)
    local root = config[FALLBACK_ROOT_KEY]
    if root == nil and create then
        root = {}
        config[FALLBACK_ROOT_KEY] = root
    end
    if type(root) ~= "table" then
        if create then
            root = {}
            config[FALLBACK_ROOT_KEY] = root
        else
            return nil
        end
    end
    return root
end

function persistentCacheStore.create(modConfig, backend)
    local store = {}

    function store.read(key)
        if backend then
            return backend.read(CACHE_SECTION, key)
        end
        local root = getFallbackRoot(modConfig, false)
        if root then
            return root[key]
        end
        return nil
    end

    function store.has(key)
        return store.read(key) ~= nil
    end

    function store.write(key, value)
        if backend then
            if backend.write(CACHE_SECTION, key, value) then
                return true
            end
            return backend.ensure(CACHE_SECTION, key, value)
        end
        local root = getFallbackRoot(modConfig, true)
        root[key] = value
        return true
    end

    function store.clear(key)
        local hadValue = store.has(key)
        if backend then
            backend.clear(CACHE_SECTION, key)
        else
            local root = getFallbackRoot(modConfig, false)
            if root then
                root[key] = nil
            end
        end
        return hadValue
    end

    return store
end

return persistentCacheStore
