local deps = ...

local retainedState = deps.state
local renderer = deps.renderer
local overlayOrder = deps.order
local rom = deps.rom
local declarations = deps.declarations

local function resolveVisibleValue(registry, visible)
    if type(visible) ~= "function" then
        return visible
    end
    if registry.explicitOwner == true then
        return visible()
    end
    return visible(registry.host, registry.runtime)
end

local function copyArray(source)
    local copy = {}
    for index, value in ipairs(source or {}) do
        copy[index] = value
    end
    return copy
end

local function copyMap(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function retainedHandleId(registry, name)
    return tostring(registry.ownerId) .. ":" .. tostring(name)
end

local function retainedRowId(registry, name, index)
    return retainedHandleId(registry, name) .. ":row:" .. tostring(index)
end

local function isRegistryVisible(registry, visible)
    if registry.hidden == true then
        return false
    end
    return resolveVisibleValue(registry, visible) ~= false
end

local function createColumnVisible(registry, visible)
    if type(visible) ~= "function" then
        return visible
    end
    return function()
        return resolveVisibleValue(registry, visible) ~= false
    end
end

local function ensureRegistryShape(registry, owner, explicitOwner)
    registry.refreshPass = registry.refreshPass or 0
    registry.owner = owner
    registry.explicitOwner = explicitOwner == true
end

local function newRegistry(owner, ownerId, explicitOwner)
    return {
        owner = owner,
        ownerId = ownerId,
        explicitOwner = explicitOwner,
        refreshPass = 0,
        refreshing = false,
        elements = {},
        events = {
            commit = {},
            intervals = {},
            afterHooks = {},
        },
    }
end

-- String owners are explicit (system/modpack) registries; table owners are module owner tokens.
local function getRegistry(owner, create)
    local explicitOwner = type(owner) == "string"
    local registries = explicitOwner and retainedState.explicitRegistries or retainedState.tableRegistries
    local registry = registries[owner]
    if not registry and create then
        local ownerId = owner
        if not explicitOwner then
            retainedState.nextOwnerId = retainedState.nextOwnerId + 1
            ownerId = "owner" .. tostring(retainedState.nextOwnerId)
        end
        registry = newRegistry(owner, ownerId, explicitOwner)
        registries[owner] = registry
    end
    if registry then
        ensureRegistryShape(registry, owner, explicitOwner)
    end
    return registry
end

local function unregisterElement(slot)
    if not slot then
        return
    end
    if slot.kind == "line" and slot.handle then
        slot.handle.unregister()
        slot.handle = nil
        return
    end
    if slot.kind == "table" and slot.handles then
        for _, handle in ipairs(slot.handles) do
            handle.unregister()
        end
        slot.handles = {}
    end
end

local function readLineColumn(slot, column)
    local valuesTable = slot.values
    if type(valuesTable) ~= "table" then
        return valuesTable
    end
    return valuesTable[column.key]
end

local function normalizeLineColumns(spec)
    if type(spec.columns) == "table" and #spec.columns > 0 then
        return spec.columns
    end
    return {
        {
            key = "text",
            minWidth = spec.minWidth,
            justify = spec.justify,
            textArgs = spec.textArgs,
        },
    }
end

local function normalizeRetainedColumn(registry, column, index, textResolver)
    return {
        key = column.key or tostring(index),
        componentName = column.componentName,
        minWidth = column.minWidth,
        justify = column.justify,
        visible = createColumnVisible(registry, column.visible),
        textArgs = column.textArgs,
        text = textResolver,
    }
end

local function createLineSlot(registry, name, spec, existingValues, isStamp)
    local slot = {
        kind = "line",
        isStamp = isStamp == true,
        name = name,
        refreshPass = registry.refreshPass,
        spec = spec,
        values = existingValues,
    }
    local columns = {}
    for index, column in ipairs(normalizeLineColumns(spec)) do
        local key = column.key or tostring(index)
        columns[#columns + 1] = normalizeRetainedColumn(registry, column, index, function()
            return readLineColumn(slot, { key = key }) or ""
        end)
    end
    slot.handle = renderer.createStackRow({
        id = retainedHandleId(registry, name),
        componentName = spec.componentName,
        region = spec.region,
        order = spec.order,
        columnGap = spec.columnGap,
        hudVisibility = spec.hudVisibility,
        isStamp = slot.isStamp,
        visible = function()
            return isRegistryVisible(registry, spec.visible)
        end,
        columns = columns,
    })
    return slot
end

local function readTableCell(slot, rowIndex, column)
    local row = slot.rows and slot.rows[rowIndex] or nil
    if type(row) ~= "table" then
        return ""
    end
    return row[column.key] or ""
end

local function createTableSlot(registry, name, spec, existingRows, existingRowIndexByKey)
    local maxRows = tonumber(spec.maxRows)
    local slot = {
        kind = "table",
        name = name,
        refreshPass = registry.refreshPass,
        spec = spec,
        rows = existingRows or {},
        rowIndexByKey = existingRowIndexByKey or {},
        handles = {},
    }

    for rowIndex = 1, maxRows do
        local columns = {}
        for columnIndex, column in ipairs(spec.columns or {}) do
            local key = column.key or tostring(columnIndex)
            columns[#columns + 1] = normalizeRetainedColumn(registry, column, columnIndex, function()
                return readTableCell(slot, rowIndex, { key = key })
            end)
        end

        slot.handles[rowIndex] = renderer.createStackRow({
            id = retainedRowId(registry, name, rowIndex),
            componentName = spec.componentName and (spec.componentName .. "_" .. tostring(rowIndex)) or nil,
            region = spec.region,
            order = (tonumber(spec.order) or overlayOrder.module) + rowIndex - 1,
            columnGap = spec.columnGap,
            hudVisibility = spec.hudVisibility,
            visible = function()
                return isRegistryVisible(registry, spec.visible) and slot.rows[rowIndex] ~= nil
            end,
            columns = columns,
        })
    end

    return slot
end

local function snapshotSlot(slot)
    if slot.kind == "line" then
        return {
            kind = slot.kind,
            name = slot.name,
            refreshPass = slot.refreshPass,
            spec = slot.spec,
            values = slot.values,
            isStamp = slot.isStamp,
        }
    end
    return {
        kind = slot.kind,
        name = slot.name,
        refreshPass = slot.refreshPass,
        spec = slot.spec,
        rows = slot.rows,
        rowIndexByKey = slot.rowIndexByKey,
    }
end

local function snapshotRegistry(registry)
    local elements = {}
    for name, slot in pairs(registry.elements) do
        elements[name] = snapshotSlot(slot)
    end
    return {
        ownerId = registry.ownerId,
        hidden = registry.hidden,
        host = registry.host,
        runtime = registry.runtime,
        refreshPass = registry.refreshPass,
        refreshing = registry.refreshing,
        elements = elements,
        events = {
            commit = copyArray(registry.events.commit),
            intervals = copyMap(registry.events.intervals),
            afterHooks = copyMap(registry.events.afterHooks),
        },
    }
end

-- Recreates element slots (and their renderer rows) from slot snapshots.
local function rebuildSlots(registry, slotSnapshots)
    registry.elements = {}
    for name, slotSnapshot in pairs(slotSnapshots) do
        local slot
        if slotSnapshot.kind == "line" then
            slot = createLineSlot(registry, name, slotSnapshot.spec, slotSnapshot.values, slotSnapshot.isStamp)
        else
            slot = createTableSlot(registry, name, slotSnapshot.spec, slotSnapshot.rows, slotSnapshot.rowIndexByKey)
        end
        slot.refreshPass = slotSnapshot.refreshPass
        registry.elements[name] = slot
    end
end

local function restoreRegistry(registry, snapshot)
    for _, slot in pairs(registry.elements) do
        unregisterElement(slot)
    end

    registry.ownerId = snapshot.ownerId
    registry.hidden = snapshot.hidden == true
    registry.host = snapshot.host
    registry.runtime = snapshot.runtime
    registry.refreshPass = snapshot.refreshPass
    registry.refreshing = snapshot.refreshing
    registry.events = {
        commit = copyArray(snapshot.events.commit),
        intervals = copyMap(snapshot.events.intervals),
        afterHooks = copyMap(snapshot.events.afterHooks),
    }
    rebuildSlots(registry, snapshot.elements)
end

local function ensureIntervalDriver()
    if retainedState.intervalDriverRegistered then
        return
    end
    if rom and rom.gui and type(rom.gui.add_always_draw_imgui) == "function" then
        -- The ImGui callback outlives Lib re-imports, so it late-reads the current dispatcher.
        rom.gui.add_always_draw_imgui(function()
            retainedState.dispatchIntervals(os.clock())
        end)
        retainedState.intervalDriverRegistered = true
    end
end

local function declareLine(registry, name, spec, isStamp)
    registry.seenElements[name] = true

    local previous = registry.elements[name]
    local previousValues = previous and previous.kind == "line" and previous.values or nil
    if previous then
        unregisterElement(previous)
    end

    registry.elements[name] = createLineSlot(registry, name, spec, previousValues, isStamp)
end

local function declareTable(registry, name, spec)
    registry.seenElements[name] = true

    local previous = registry.elements[name]
    local previousRows = previous and previous.kind == "table" and previous.rows or nil
    local previousRowIndexByKey = previous and previous.kind == "table" and previous.rowIndexByKey or nil
    if previous then
        unregisterElement(previous)
    end

    registry.elements[name] = createTableSlot(
        registry,
        name,
        spec,
        previousRows,
        previousRowIndexByKey
    )
end

local function registerCommitProjection(registry, callback)
    registry.pendingEvents.commit[#registry.pendingEvents.commit + 1] = callback
end

local function registerIntervalProjection(registry, name, seconds, callback, opts)
    registry.pendingEvents.intervals[name] = {
        name = name,
        seconds = seconds,
        callback = callback,
        opts = opts or {},
        lastRun = registry.events.intervals[name] and registry.events.intervals[name].lastRun or nil,
    }
    ensureIntervalDriver()
end

local function registerAfterHookProjection(registry, path, callback)
    registry.pendingEvents.afterHooks[path] = {
        path = path,
        callback = callback,
    }
end

-- System defines hand this surface to author code, so it validates; the module surface only
-- replays declarations validated when they were declared.
local function createDeclarationSurface(registry, opts)
    if opts and opts.system == true then
        return {
            createStamp = function(name, spec)
                declarations.validateLine("system.overlays.createStamp", name, spec)
                return declareLine(registry, name, spec, true)
            end,
            createLine = function(name, spec)
                declarations.validateLine("system.overlays.createLine", name, spec)
                return declareLine(registry, name, spec)
            end,
            onCommit = function(callback)
                declarations.validateCallback("system.overlays.onCommit", callback)
                return registerCommitProjection(registry, callback)
            end,
        }
    end

    return {
        createLine = function(name, spec)
            return declareLine(registry, name, spec)
        end,
        createTable = function(name, spec)
            return declareTable(registry, name, spec)
        end,
        onCommit = function(callback)
            return registerCommitProjection(registry, callback)
        end,
        onInterval = function(name, seconds, callback, intervalOpts)
            return registerIntervalProjection(registry, name, seconds, callback, intervalOpts)
        end,
        afterHook = function(path, callback)
            return registerAfterHookProjection(registry, path, callback)
        end,
    }
end

local function beginTransaction(owner)
    local registry = getRegistry(owner, true)
    local snapshot = snapshotRegistry(registry)
    local closed = false

    return {
        commit = function()
            closed = true
        end,
        rollback = function()
            if closed then
                return
            end
            restoreRegistry(registry, snapshot)
            closed = true
        end,
    }
end

local function refresh(owner, ownerId, host, runtime, register, opts)
    local registry = getRegistry(owner, true)
    registry.ownerId = ownerId
    registry.hidden = opts and opts.hidden == true
    registry.host = host
    registry.runtime = runtime
    registry.refreshPass = registry.refreshPass + 1
    registry.refreshing = true
    registry.seenElements = {}
    registry.pendingEvents = {
        commit = {},
        intervals = {},
        afterHooks = {},
    }

    local ok, err = pcall(register, createDeclarationSurface(registry, opts))
    registry.refreshing = false

    if ok then
        for name, slot in pairs(registry.elements) do
            if not registry.seenElements[name] then
                unregisterElement(slot)
                registry.elements[name] = nil
            else
                slot.refreshPass = registry.refreshPass
            end
        end
        registry.events = registry.pendingEvents
    end

    registry.seenElements = nil
    registry.pendingEvents = nil

    if not ok then
        error(err, 0)
    end
end

local function getAfterHookPaths(owner)
    local paths = {}
    for path in pairs(getRegistry(owner, false).events.afterHooks) do
        paths[#paths + 1] = path
    end
    table.sort(paths)
    return paths
end

-- Re-registers the registry's rows so their renderer ids follow its (possibly changed) ownerId.
local function recreateElementSlots(registry)
    local snapshots = {}
    for name, slot in pairs(registry.elements) do
        snapshots[name] = snapshotSlot(slot)
        unregisterElement(slot)
    end
    rebuildSlots(registry, snapshots)
end

local function promoteTableRegistry(sourceOwner, targetOwner, ownerId, host, runtime)
    local registry = getRegistry(sourceOwner, false)
    if not registry then
        return
    end

    local previousTargetRegistry = retainedState.tableRegistries[targetOwner]
    if previousTargetRegistry and previousTargetRegistry ~= registry then
        for _, slot in pairs(previousTargetRegistry.elements or {}) do
            unregisterElement(slot)
        end
    end

    retainedState.tableRegistries[sourceOwner] = nil
    retainedState.tableRegistries[targetOwner] = registry
    ensureRegistryShape(registry, targetOwner, false)
    registry.ownerId = ownerId
    registry.hidden = false
    registry.host = host
    registry.runtime = runtime
    recreateElementSlots(registry)
end

-- Clears every table-owned registry promoted under `ownerId` except `exceptOwner`.
-- Returns the cleared registries' snapshots (also on failure, for what was cleared), so a
-- caller that later rolls back can hand them to `restoreTableRegistries`.
local function clearTableRegistriesByOwnerId(ownerId, exceptOwner)
    local owners = {}
    for owner, registry in pairs(retainedState.tableRegistries) do
        if owner ~= exceptOwner and registry.ownerId == ownerId then
            owners[#owners + 1] = owner
        end
    end

    local cleared = {}
    local errors = {}
    for _, owner in ipairs(owners) do
        local registry = getRegistry(owner, false)
        local snapshot = snapshotRegistry(registry)
        local ok, err = pcall(refresh, owner, ownerId, nil, nil, function() end)
        if ok then
            cleared[#cleared + 1] = {
                registry = registry,
                snapshot = snapshot,
            }
        else
            restoreRegistry(registry, snapshot)
            errors[#errors + 1] = tostring(err)
        end
    end

    if #errors > 0 then
        return false, table.concat(errors, "; "), cleared
    end
    return true, nil, cleared
end

-- Reinstates registries cleared by `clearTableRegistriesByOwnerId`, newest clear first.
local function restoreTableRegistries(cleared)
    for index = #cleared, 1, -1 do
        restoreRegistry(cleared[index].registry, cleared[index].snapshot)
    end
end

local dispatch = import('core/overlays/retained_dispatch.lua', nil, {
    state = retainedState,
    renderer = renderer,
    getRegistry = getRegistry,
})
-- Refreshed every import so the persistent interval driver dispatches through current code.
retainedState.dispatchIntervals = dispatch.dispatchIntervals

return {
    beginTransaction = beginTransaction,
    refresh = refresh,
    getAfterHookPaths = getAfterHookPaths,
    promoteTableRegistry = promoteTableRegistry,
    clearTableRegistriesByOwnerId = clearTableRegistriesByOwnerId,
    restoreTableRegistries = restoreTableRegistries,
    dispatchCommit = dispatch.dispatchCommit,
    dispatchAfterHook = dispatch.dispatchAfterHook,
}
