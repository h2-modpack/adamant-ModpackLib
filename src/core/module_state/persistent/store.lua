local deps = ...

local phaseGate = deps.phaseGate
local storageRefAdapter = deps.storageRefAdapter

local store = {}

---@param persistentState PersistentState
---@param cache table|nil
---@param shared table|nil
---@return Store
function store.create(persistentState, cache, shared)
    local refs = storageRefAdapter.create({
        root = persistentState,
        phase = "runtime",
        source = "store.get",
        writable = false,
    })
    local runtimeOwnedRefs = storageRefAdapter.create({
        root = persistentState.runtimeOwned,
        phase = "runtime",
        source = "store.runtimeOwned.get",
        writable = false,
    })

    local runtimeOwned = persistentState.runtimeOwned

    return {
        get = refs.get,
        cache = cache,
        shared = shared,
        runtimeOwned = runtimeOwned and {
            get = runtimeOwnedRefs.get,
            read = function(alias)
                storageRefAdapter.rejectPrivateAlias("store.runtimeOwned.read", alias)
                return runtimeOwned.read(alias)
            end,
            set = function(alias, value)
                phaseGate.requireRuntime()
                storageRefAdapter.rejectPrivateAlias("store.runtimeOwned.set", alias)
                return runtimeOwned.set(alias, value)
            end,
            clear = function(alias)
                phaseGate.requireRuntime()
                storageRefAdapter.rejectPrivateAlias("store.runtimeOwned.clear", alias)
                return runtimeOwned.clear(alias)
            end,
        } or nil,
        read = function(alias, ...)
            storageRefAdapter.rejectPrivateAlias("store.read", alias)
            local ref = persistentState.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
    }
end

return store
