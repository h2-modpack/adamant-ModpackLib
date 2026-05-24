local snapshotObject = {}

function snapshotObject.create(adapter)
    local snapshot = adapter.load()
    local ref = {}

    ref.get = function()
        if snapshot == nil and adapter.get then
            snapshot = adapter.get()
        end
        if adapter.copy then
            return adapter.copy(snapshot)
        end
        return snapshot
    end

    ref.refresh = function()
        if adapter.refresh then
            snapshot = adapter.refresh()
        else
            snapshot = adapter.load()
        end
        if adapter.copy then
            return adapter.copy(snapshot)
        end
        return snapshot
    end

    if adapter.write then
        ref.set = function(selfOrValue, maybeValue)
            local value = maybeValue
            if selfOrValue ~= ref then
                value = selfOrValue
            end
            local ok, nextSnapshot = adapter.write(value)
            if ok then
                snapshot = nextSnapshot
            end
            return ok
        end
    end

    if adapter.clear then
        ref.clear = function()
            local ok, nextSnapshot = adapter.clear()
            snapshot = nextSnapshot
            return ok
        end
    end

    if adapter.has then
        ref.has = function()
            return adapter.has()
        end
    end

    if adapter.peek then
        ref.peek = function()
            snapshot = adapter.peek()
            if adapter.copy then
                return adapter.copy(snapshot)
            end
            return snapshot
        end
    end

    return ref
end

return snapshotObject
