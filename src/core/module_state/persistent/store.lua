local deps = ...

local phaseGate = deps.phaseGate
local storageRefAdapter = deps.storageRefAdapter

local store = {}

---@param persistentState PersistentState
---@return Store
function store.create(persistentState)
    local refs = storageRefAdapter.create({
        root = persistentState,
        phase = "runtime",
        source = "store.get",
        writable = false,
    })

    return {
        get = refs.get,
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
