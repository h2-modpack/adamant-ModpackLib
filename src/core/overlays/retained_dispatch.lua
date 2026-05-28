local deps = ...

local getRegistry = deps.getRegistry
local logging = deps.logging
local renderer = deps.renderer

local function createProjectionContext(registry)
    local host = registry.host
    local store = registry.store
    local ctx = {}

    function ctx.read(alias)
        if store and type(store.read) == "function" then
            return store.read(alias)
        end
        return nil
    end

    function ctx.isEnabled()
        if host and type(host.isEnabled) == "function" then
            return host.isEnabled()
        end
        return true
    end

    function ctx.log(fmt, ...)
        if host and type(host.log) == "function" then
            return host.log(fmt, ...)
        end
        print(logging.formatLogMessage("[overlays:" .. tostring(registry.ownerId) .. "] ", fmt, ...))
    end

    function ctx.logIf(fmt, ...)
        if host and type(host.logIf) == "function" then
            return host.logIf(fmt, ...)
        end
    end

    function ctx.setLine(name, valuesTable)
        local slot = registry.elements[name]
        if slot and slot.kind == "line" then
            slot.values = valuesTable
            return true
        end
        return false
    end

    function ctx.setTable(name, rows)
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

    function ctx.setCell(tableName, rowKey, columnKey, value)
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

    function ctx.refresh(name)
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

    function ctx.refreshRegion(region)
        renderer.refreshStackRows(region)
    end

    function ctx.refreshAll()
        renderer.refreshStackRows()
        renderer.refreshTextElements(true)
    end

    return ctx
end

local function dispatchCommit(owner, commit)
    local registry = getRegistry(owner, false)
    if not registry then
        return
    end
    if registry.hidden == true then
        return
    end

    local ctx = createProjectionContext(registry)
    for _, callback in ipairs(registry.events.commit or {}) do
        callback(ctx, commit)
    end
end

local function dispatchIntervals(now)
    now = tonumber(now) or os.clock()
    local function dispatchRegistry(registry)
        if registry.hidden == true then
            return
        end
        local ctx = nil
        for _, event in pairs(registry.events.intervals or {}) do
            local shouldRun = true
            if event.opts and type(event.opts.when) == "function" then
                shouldRun = event.opts.when() == true
            end
            if shouldRun and (event.lastRun == nil or now - event.lastRun >= event.seconds) then
                event.lastRun = now
                ctx = ctx or createProjectionContext(registry)
                event.callback(ctx, {
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

    local ctx = createProjectionContext(registry)
    event.callback(ctx, {
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
