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

    return {
        get = refs.get,
        cache = cache,
        shared = shared,
        read = function(alias, ...)
            phaseGate.requireRuntime()
            local ref = persistentState.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
    }
end

return store
