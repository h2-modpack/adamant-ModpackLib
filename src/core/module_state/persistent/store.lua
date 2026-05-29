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

    local runtime = persistentState.runtime

    return {
        get = refs.get,
        cache = cache,
        shared = shared,
        runtime = runtime and {
            read = function(alias)
                phaseGate.requireRuntime()
                storageRefAdapter.rejectPrivateAlias("store.runtime.read", alias)
                return runtime.read(alias)
            end,
            set = function(alias, value)
                phaseGate.requireRuntime()
                storageRefAdapter.rejectPrivateAlias("store.runtime.set", alias)
                return runtime.set(alias, value)
            end,
            clear = function(alias)
                phaseGate.requireRuntime()
                storageRefAdapter.rejectPrivateAlias("store.runtime.clear", alias)
                return runtime.clear(alias)
            end,
        } or nil,
        read = function(alias, ...)
            phaseGate.requireRuntime()
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
