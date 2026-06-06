local deps = ...

local logging = deps.logging
local storageRefAdapter = deps.storageRefAdapter

local store = {}

local function createDataRoot(persistentState)
    return {
        get = function(alias)
            local node = persistentState.getAliasSchema(alias)
            if node and node._mode == "runtime" then
                logging.violate(
                    "store.invalid_surface",
                    "runtime.data.get: alias '%s' is status, not data storage",
                    tostring(alias))
                return nil
            end
            return persistentState.get(alias)
        end,
    }
end

---@param persistentState PersistentState
---@param cache table|nil
---@param shared table|nil
---@return Store
function store.create(persistentState, cache, shared)
    local refs = storageRefAdapter.create({
        root = createDataRoot(persistentState),
        phase = "runtime",
        source = "runtime.data.get",
        writable = false,
    })

    return {
        get = refs.get,
        cache = cache,
        shared = shared,
        read = function(alias, ...)
            storageRefAdapter.rejectPrivateAlias("runtime.data.read", alias)
            local ref = refs.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
    }
end

return store
