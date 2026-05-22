local deps = ...

local phaseGate = deps.phaseGate
local storageRefAdapter = deps.storageRefAdapter

local store = {}

---@param persistentState PersistentState
---@param phaseOwner table
---@return Store
function store.create(persistentState, phaseOwner)
    local refs = storageRefAdapter.create({
        root = persistentState,
        phaseOwner = phaseOwner,
        phase = "runtime",
        source = "store.get",
        writable = false,
    })

    return {
        get = refs.get,
        read = function(alias, ...)
            phaseGate.requireRuntime(phaseOwner)
            local ref = persistentState.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
    }
end

return store
