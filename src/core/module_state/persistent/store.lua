local store = {}

---@param persistentState PersistentState
---@return Store
function store.create(persistentState)
    return {
        get = persistentState.get,
        read = function(alias, ...)
            local ref = persistentState.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
    }
end

return store
