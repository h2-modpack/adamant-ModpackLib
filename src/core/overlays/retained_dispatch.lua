local deps = ...

local getRegistry = deps.getRegistry
local renderer = deps.renderer

local function createOverlayProjection(registry)
    local overlay = {}

    function overlay.setLine(name, valuesTable)
        local slot = registry.elements[name]
        if slot and slot.kind == "line" then
            slot.values = valuesTable
            return true
        end
        return false
    end

    function overlay.setTable(name, rows)
        local slot = registry.elements[name]
        if not (slot and slot.kind == "table") then
            return false
        end
        slot.rows = {}
        slot.rowIndexByKey = {}
        for index, row in ipairs(rows or {}) do
            if index > #slot.handles then
                break
            end
            slot.rows[index] = row
            if type(row) == "table" and row.key ~= nil then
                slot.rowIndexByKey[row.key] = index
            end
        end
        return true
    end

    function overlay.setCell(tableName, rowKey, columnKey, value)
        local slot = registry.elements[tableName]
        if not (slot and slot.kind == "table") then
            return false
        end
        local rowIndex = slot.rowIndexByKey[rowKey]
        local row = rowIndex and slot.rows[rowIndex] or nil
        if type(row) ~= "table" then
            return false
        end
        row[columnKey] = value
        return true
    end

    function overlay.refresh(name)
        local slot = registry.elements[name]
        if not slot then
            return false
        end
        if slot.kind == "line" then
            slot.handle.refresh()
        elseif slot.kind == "table" then
            for _, handle in ipairs(slot.handles) do
                handle.refresh()
            end
        end
        return true
    end

    function overlay.refreshRegion(region)
        renderer.refreshStackRows(region)
    end

    function overlay.refreshAll()
        renderer.refreshStackRows()
        renderer.refreshTextElements(true)
    end

    return overlay
end

local function createRuntimeContext(registry)
    if registry.runtime ~= nil then
        return registry.runtime
    end
    local store = registry.store
    return {
        data = store,
        cache = store and store.cache or nil,
        shared = store and store.shared or nil,
        controls = store and store.controls or nil,
    }
end

local function dispatchProjection(registry, callback, event)
    local overlay = createOverlayProjection(registry)
    if registry.explicitOwner == true then
        callback(overlay, event)
        return
    end
    callback(registry.host, createRuntimeContext(registry), overlay, event)
end

local function shouldDispatchInterval(registry, event)
    local when = event.opts and event.opts.when or nil
    if type(when) ~= "function" then
        return true
    end
    local intervalEvent = {
        name = event.name,
        now = event.now,
    }
    if registry.explicitOwner == true then
        return when(intervalEvent) == true
    end
    return when(registry.host, createRuntimeContext(registry), intervalEvent) == true
end

local function dispatchCommit(owner, commit)
    local registry = getRegistry(owner, false)
    if not registry then
        return
    end
    if registry.hidden == true then
        return
    end

    for _, callback in ipairs(registry.events.commit or {}) do
        dispatchProjection(registry, callback, commit)
    end
end

local function dispatchIntervals(now)
    now = tonumber(now) or os.clock()
    local function dispatchRegistry(registry)
        if registry.hidden == true then
            return
        end
        for _, event in pairs(registry.events.intervals or {}) do
            event.now = now
            local shouldRun = shouldDispatchInterval(registry, event)
            if shouldRun and (event.lastRun == nil or now - event.lastRun >= event.seconds) then
                event.lastRun = now
                dispatchProjection(registry, event.callback, {
                    name = event.name,
                    now = now,
                })
            end
        end
    end

    for _, registry in pairs(deps.state.explicitRegistries) do
        dispatchRegistry(registry)
    end
    for _, registry in pairs(deps.state.tableRegistries) do
        if registry.explicitOwner ~= true then
            dispatchRegistry(registry)
        end
    end
end

local function dispatchAfterHook(owner, path, args, results)
    local registry = getRegistry(owner, false)
    local event = registry and registry.events.afterHooks and registry.events.afterHooks[path] or nil
    if not event then
        return
    end
    if registry.hidden == true then
        return
    end

    dispatchProjection(registry, event.callback, {
        path = path,
        args = args or {},
        result = results and results[1] or nil,
        results = results or {},
    })
end

return {
    dispatchCommit = dispatchCommit,
    dispatchIntervals = dispatchIntervals,
    dispatchAfterHook = dispatchAfterHook,
}
