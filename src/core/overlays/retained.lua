local deps = ...

local retainedState = deps.state
local renderer = deps.renderer
local logging = deps.logging
local overlayOrder = deps.order
local rom = deps.rom

local function getRuntimeContext(registry)
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

local function resolveVisibleValue(registry, visible)
    if type(visible) ~= "function" then
        return visible
    end
    if registry.explicitOwner == true then
        return visible()
    end
    return visible(registry.host, getRuntimeContext(registry))
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

local function validateName(apiName, name)
    if type(name) ~= "string" or name == "" then
        logging.violate("overlays.invalid_registration", "retained overlays.%s: name must be a non-empty string", apiName)
    end
end

local function validateSpec(apiName, spec)
    if type(spec) ~= "table" then
        logging.violate("overlays.invalid_registration", "retained overlays.%s: spec must be a table", apiName)
    end
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

local function getRegistry(owner, create)
    if type(owner) == "string" then
        local registry = retainedState.explicitRegistries[owner]
        if not registry and create then
            registry = {
                owner = owner,
                ownerId = owner,
                explicitOwner = true,
                refreshPass = 0,
                refreshing = false,
                elements = {},
                events = {
                    commit = {},
                    intervals = {},
                    afterHooks = {},
                },
            }
            retainedState.explicitRegistries[owner] = registry
        end
        if registry then
            ensureRegistryShape(registry, owner, true)
        end
        return registry
    end

    if type(owner) ~= "table" then
        logging.violate("overlays.invalid_registration", "retained overlays: owner must be a persistent table or string")
    end

    local registry = retainedState.tableRegistries[owner]
    if not registry and create then
        retainedState.nextOwnerId = retainedState.nextOwnerId + 1
        registry = {
            owner = owner,
            ownerId = "owner" .. tostring(retainedState.nextOwnerId),
            refreshPass = 0,
            refreshing = false,
            elements = {},
            events = {
                commit = {},
                intervals = {},
                afterHooks = {},
            },
        }
        retainedState.tableRegistries[owner] = registry
    end
    if registry then
        ensureRegistryShape(registry, owner, false)
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

local function createLineSlot(registry, name, spec, existingValues)
    local slot = {
        kind = "line",
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
    local maxRows = math.max(0, math.floor(tonumber(spec.maxRows) or 0))
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
        store = registry.store,
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

local function restoreRegistry(registry, snapshot)
    for _, slot in pairs(registry.elements) do
        unregisterElement(slot)
    end

    registry.ownerId = snapshot.ownerId
    registry.hidden = snapshot.hidden == true
    registry.host = snapshot.host
    registry.runtime = snapshot.runtime
    registry.store = snapshot.store
    registry.refreshPass = snapshot.refreshPass
    registry.refreshing = snapshot.refreshing
    registry.events = {
        commit = copyArray(snapshot.events.commit),
        intervals = copyMap(snapshot.events.intervals),
        afterHooks = copyMap(snapshot.events.afterHooks),
    }
    registry.elements = {}

    for name, slotSnapshot in pairs(snapshot.elements) do
        if slotSnapshot.kind == "line" then
            local slot = createLineSlot(registry, name, slotSnapshot.spec, slotSnapshot.values)
            slot.refreshPass = slotSnapshot.refreshPass
            registry.elements[name] = slot
        elseif slotSnapshot.kind == "table" then
            local slot = createTableSlot(
                registry,
                name,
                slotSnapshot.spec,
                slotSnapshot.rows,
                slotSnapshot.rowIndexByKey
            )
            slot.refreshPass = slotSnapshot.refreshPass
            registry.elements[name] = slot
        end
    end
end

local function ensureIntervalDriver()
    if retainedState.intervalDriverRegistered then
        return
    end
    retainedState.intervalDriverRegistered = true
    if rom and rom.gui and type(rom.gui.add_always_draw_imgui) == "function" then
        rom.gui.add_always_draw_imgui(function()
            deps.dispatchIntervals(os.clock())
        end)
    end
end

local function declareLine(registry, name, spec)
    validateName("createLine", name)
    validateSpec("createLine", spec)
    registry.seenElements[name] = true

    local previous = registry.elements[name]
    local previousValues = previous and previous.kind == "line" and previous.values or nil
    if previous then
        unregisterElement(previous)
    end

    registry.elements[name] = createLineSlot(registry, name, spec, previousValues)
end

local function declareTable(registry, name, spec)
    validateName("createTable", name)
    validateSpec("createTable", spec)
    if type(spec.columns) ~= "table" or #spec.columns == 0 then
        logging.violate(
            "overlays.invalid_registration",
            "retained overlays.createTable: columns must be a non-empty array"
        )
    end
    local maxRows = tonumber(spec.maxRows)
    if not maxRows or maxRows < 1 or math.floor(maxRows) ~= maxRows then
        logging.violate(
            "overlays.invalid_registration",
            "retained overlays.createTable: maxRows must be a positive integer"
        )
    end
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
    if type(callback) ~= "function" then
        logging.violate("overlays.invalid_registration", "retained overlays.onCommit: callback must be a function")
    end
    registry.pendingEvents.commit[#registry.pendingEvents.commit + 1] = callback
end

local function registerIntervalProjection(registry, name, seconds, callback, opts)
    validateName("onInterval", name)
    if type(callback) ~= "function" then
        logging.violate("overlays.invalid_registration", "retained overlays.onInterval: callback must be a function")
    end
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then
        logging.violate("overlays.invalid_registration", "retained overlays.onInterval: seconds must be positive")
    end
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
    validateName("afterHook", path)
    if type(callback) ~= "function" then
        logging.violate("overlays.invalid_registration", "retained overlays.afterHook: callback must be a function")
    end
    registry.pendingEvents.afterHooks[path] = {
        path = path,
        callback = callback,
    }
end

local function createDeclarationSurface(registry, opts)
    if opts and opts.system == true then
        return {
            createLine = function(name, spec)
                return declareLine(registry, name, spec)
            end,
            onCommit = function(callback)
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
    if type(register) ~= "function" then
        logging.violate("overlays.invalid_registration", "overlay refresh: register must be a function")
    end

    local registry = getRegistry(owner, true)
    if type(ownerId) == "string" and ownerId ~= "" then
        registry.ownerId = ownerId
    end
    registry.hidden = opts and opts.hidden == true
    registry.host = host
    registry.runtime = runtime
    registry.store = runtime and runtime.data or nil
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
    local registry = getRegistry(owner, false)
    local paths = {}
    local afterHooks = registry and registry.events and registry.events.afterHooks or nil
    for path in pairs(afterHooks or {}) do
        paths[#paths + 1] = path
    end
    table.sort(paths)
    return paths
end

local function recreateElementSlots(registry)
    local snapshots = {}
    for name, slot in pairs(registry.elements) do
        snapshots[name] = snapshotSlot(slot)
        unregisterElement(slot)
    end

    registry.elements = {}
    for name, slotSnapshot in pairs(snapshots) do
        if slotSnapshot.kind == "line" then
            local slot = createLineSlot(registry, name, slotSnapshot.spec, slotSnapshot.values)
            slot.refreshPass = slotSnapshot.refreshPass
            registry.elements[name] = slot
        elseif slotSnapshot.kind == "table" then
            local slot = createTableSlot(
                registry,
                name,
                slotSnapshot.spec,
                slotSnapshot.rows,
                slotSnapshot.rowIndexByKey
            )
            slot.refreshPass = slotSnapshot.refreshPass
            registry.elements[name] = slot
        end
    end
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
    if type(ownerId) == "string" and ownerId ~= "" then
        registry.ownerId = ownerId
    end
    registry.hidden = false
    registry.host = host
    registry.runtime = runtime
    registry.store = runtime and runtime.data or nil
    recreateElementSlots(registry)
end

local function clearTableRegistriesByOwnerId(ownerId, exceptOwner)
    if type(ownerId) ~= "string" or ownerId == "" then
        return true, nil
    end

    local owners = {}
    for owner, registry in pairs(retainedState.tableRegistries) do
        if owner ~= exceptOwner and registry.ownerId == ownerId then
            owners[#owners + 1] = owner
        end
    end

    local errors = {}
    for _, owner in ipairs(owners) do
        local transaction = beginTransaction(owner)
        local ok, err = pcall(refresh, owner, ownerId, nil, nil, function() end)
        if ok then
            transaction.commit()
        else
            transaction.rollback()
            errors[#errors + 1] = tostring(err)
        end
    end

    if #errors > 0 then
        return false, table.concat(errors, "; ")
    end
    return true, nil
end

local dispatch = import('core/overlays/retained_dispatch.lua', nil, {
    state = retainedState,
    renderer = renderer,
    getRegistry = getRegistry,
    logging = logging,
})

return {
    beginTransaction = beginTransaction,
    refresh = refresh,
    getAfterHookPaths = getAfterHookPaths,
    promoteTableRegistry = promoteTableRegistry,
    clearTableRegistriesByOwnerId = clearTableRegistriesByOwnerId,
    dispatchCommit = dispatch.dispatchCommit,
    dispatchIntervals = dispatch.dispatchIntervals,
    dispatchAfterHook = dispatch.dispatchAfterHook,
}
