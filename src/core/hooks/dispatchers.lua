local deps = ...
local hookRegistry = deps.hookRegistry
local logging = deps.logging
local modutilHooks = import('core/hooks/modutil_registry.lua', nil, {
    modutil = deps.modutil,
    logging = deps.logging,
    registryKey = hookRegistry.modutilOwnerKey,
})

-- `dispatchers` own the installed ModUtil adapter for each path.
-- `ownerSlots` choose which owner object for an owner id is currently visible to those adapters.
-- Both tables are hot-reload-stable because ModUtil wrappers close over them.
local ownerSlots = hookRegistry.ownerSlots
local dispatchers = hookRegistry.dispatchers
local MODUTIL_DISPATCHER_KEY = "__hook_dispatcher"

local function getOwnerSlot(ownerId)
    local slot = ownerSlots[ownerId]
    if not slot then
        slot = {}
        ownerSlots[ownerId] = slot
    end
    return slot
end

local function getCurrentOwner(ownerId)
    local slot = ownerSlots[ownerId]
    return slot and slot.currentOwner or nil
end

local function getDispatcher(kind, path)
    local bucket = dispatchers[kind]
    local dispatcher = bucket[path]
    if not dispatcher then
        dispatcher = {
            kind = kind,
            path = path,
            modutilOwner = {},
            ownerOrder = {},
            ownerSeen = {},
            handlers = {},
            installed = false,
        }
        bucket[path] = dispatcher
    end
    dispatcher.modutilOwner = dispatcher.modutilOwner or {}
    dispatcher.ownerSeen = dispatcher.ownerSeen or {}
    dispatcher.handlers = dispatcher.handlers or {}
    return dispatcher
end

local function addOwnerOrder(dispatcher, ownerId)
    if dispatcher.ownerSeen[ownerId] then
        return
    end
    dispatcher.ownerSeen[ownerId] = true
    dispatcher.ownerOrder[#dispatcher.ownerOrder + 1] = ownerId
end

local function getCommittedOwnerSlots(dispatcher, ownerId)
    local owner = getCurrentOwner(ownerId)
    local byOwner = dispatcher.handlers[ownerId]
    return owner and byOwner and byOwner[owner] or nil
end

local function removeSlotKey(ownerSlotsForObject, key, expectedSlot)
    if ownerSlotsForObject.slots[key] ~= expectedSlot then
        return
    end

    ownerSlotsForObject.slots[key] = nil
    for index = #ownerSlotsForObject.order, 1, -1 do
        if ownerSlotsForObject.order[index] == key then
            table.remove(ownerSlotsForObject.order, index)
            return
        end
    end
end

local refreshOverrideDispatcher

local function dispatcherHasOwnerHandlers(dispatcher, ownerId)
    local byOwner = dispatcher.handlers[ownerId]
    return type(byOwner) == "table" and next(byOwner) ~= nil
end

local function dispatcherHasAnyHandlers(dispatcher)
    for ownerId in pairs(dispatcher.handlers or {}) do
        if dispatcherHasOwnerHandlers(dispatcher, ownerId) then
            return true
        end
    end
    return false
end

local function removeOwnerOrder(dispatcher, ownerId)
    if not dispatcher.ownerSeen[ownerId] then
        return
    end

    dispatcher.ownerSeen[ownerId] = nil
    for index = #dispatcher.ownerOrder, 1, -1 do
        if dispatcher.ownerOrder[index] == ownerId then
            table.remove(dispatcher.ownerOrder, index)
            return
        end
    end
end

local function pruneDispatcherOwner(dispatcher, ownerId)
    if dispatcherHasOwnerHandlers(dispatcher, ownerId) then
        return
    end
    dispatcher.handlers[ownerId] = nil
    removeOwnerOrder(dispatcher, ownerId)
end

local function pruneDispatcher(kind, path, dispatcher)
    if dispatcherHasAnyHandlers(dispatcher) then
        return
    end

    dispatcher.ownerOrder = {}
    dispatcher.ownerSeen = {}

    -- Wrap/context dispatchers are also the installed ModUtil wrapper anchors.
    -- Keep those path entries so a future registration reuses the same wrapper.
    if kind == "override" and not dispatcher.installed then
        dispatchers.override[path] = nil
    end
end

local function pruneOwnerSlot(ownerId)
    if not ownerSlots[ownerId] then
        return
    end

    for _, dispatcherBucket in pairs(dispatchers) do
        for _, dispatcher in pairs(dispatcherBucket) do
            if dispatcherHasOwnerHandlers(dispatcher, ownerId) then
                return
            end
        end
    end

    ownerSlots[ownerId] = nil
end

local function wrapChain(handler, nextBase)
    return function(...)
        return handler(nextBase, ...)
    end
end

local function dispatchWrap(dispatcher, base, ...)
    local chain = base
    for ownerIndex = 1, #dispatcher.ownerOrder do
        local ownerId = dispatcher.ownerOrder[ownerIndex]
        local ownerSlotsForObject = getCommittedOwnerSlots(dispatcher, ownerId)
        if ownerSlotsForObject then
            for slotIndex = 1, #ownerSlotsForObject.order do
                local slot = ownerSlotsForObject.slots[ownerSlotsForObject.order[slotIndex]]
                if slot and slot.value ~= nil then
                    chain = wrapChain(slot.value, chain)
                end
            end
        end
    end
    return chain(...)
end

local function dispatchContextWrap(dispatcher, ...)
    for ownerIndex = #dispatcher.ownerOrder, 1, -1 do
        local ownerId = dispatcher.ownerOrder[ownerIndex]
        local ownerSlotsForObject = getCommittedOwnerSlots(dispatcher, ownerId)
        if ownerSlotsForObject then
            for slotIndex = #ownerSlotsForObject.order, 1, -1 do
                local slot = ownerSlotsForObject.slots[ownerSlotsForObject.order[slotIndex]]
                if slot and slot.value ~= nil then
                    slot.value(...)
                end
            end
        end
    end
end

local function resolveOverride(dispatcher)
    for ownerIndex = #dispatcher.ownerOrder, 1, -1 do
        local ownerId = dispatcher.ownerOrder[ownerIndex]
        local ownerSlotsForObject = getCommittedOwnerSlots(dispatcher, ownerId)
        if ownerSlotsForObject then
            for slotIndex = #ownerSlotsForObject.order, 1, -1 do
                local slot = ownerSlotsForObject.slots[ownerSlotsForObject.order[slotIndex]]
                if slot and slot.value ~= nil then
                    return slot.value
                end
            end
        end
    end
    return nil
end

local function dispatchOverride(dispatcher, ...)
    local replacement = resolveOverride(dispatcher)
    if replacement then
        return replacement(...)
    end
    return nil
end

local function modutilDispatcherIsCurrent(dispatcher)
    return dispatcher.installed and modutilHooks.getPathTarget(dispatcher.path) == dispatcher.installedTarget
end

local function resetModUtilDispatcher(dispatcher)
    dispatcher.modutilOwner = {}
    dispatcher.installed = false
    dispatcher.installedTarget = nil
    dispatcher.state = nil
end

local function validateScopedWrap(path, handler)
    if type(path) ~= "string" or path == "" then
        logging.violate("hooks.invalid_registration", "module.hooks.contextWrap context.wrap: path must be a non-empty string")
    end
    if type(handler) ~= "function" then
        logging.violate("hooks.invalid_registration", "module.hooks.contextWrap context.wrap: handler must be a function")
    end
end

local function createContextSurface()
    local closed = false
    return {
        wrap = function(path, handler)
            if closed then
                logging.violate(
                    "hooks.invalid_context",
                    "module.hooks.contextWrap context.wrap cannot be called after the context callback returns"
                )
            end
            validateScopedWrap(path, handler)
            return modutilHooks.installScopedWrap(path, handler)
        end,
    }, function()
        closed = true
    end
end

local function ensureWrapDispatcher(dispatcher)
    if modutilDispatcherIsCurrent(dispatcher) then
        return
    end
    if dispatcher.installed then
        resetModUtilDispatcher(dispatcher)
    end
    modutilHooks.installWrap(dispatcher.modutilOwner, dispatcher.path, MODUTIL_DISPATCHER_KEY, function(base, ...)
        return dispatchWrap(dispatcher, base, ...)
    end)
    dispatcher.installed = true
    dispatcher.installedTarget = modutilHooks.getPathTarget(dispatcher.path)
end

local function ensureContextWrapDispatcher(dispatcher)
    if modutilDispatcherIsCurrent(dispatcher) then
        return
    end
    if dispatcher.installed then
        resetModUtilDispatcher(dispatcher)
    end
    modutilHooks.installContextWrap(dispatcher.modutilOwner, dispatcher.path, MODUTIL_DISPATCHER_KEY, function(...)
        return dispatchContextWrap(dispatcher, ...)
    end)
    dispatcher.installed = true
    dispatcher.installedTarget = modutilHooks.getPathTarget(dispatcher.path)
end

function refreshOverrideDispatcher(dispatcher)
    local replacement = resolveOverride(dispatcher)
    if replacement ~= nil then
        if modutilDispatcherIsCurrent(dispatcher) then
            return
        end
        if dispatcher.installed then
            resetModUtilDispatcher(dispatcher)
        end
        dispatcher.state = modutilHooks.installOverride(dispatcher.modutilOwner, dispatcher.path, MODUTIL_DISPATCHER_KEY, function(...)
            return dispatchOverride(dispatcher, ...)
        end)
        dispatcher.installed = true
        dispatcher.installedTarget = modutilHooks.getPathTarget(dispatcher.path)
        return
    end

    if dispatcher.installed and dispatcher.state then
        modutilHooks.deactivateSlot(dispatcher.state)
        dispatcher.installed = false
        dispatcher.installedTarget = nil
        dispatcher.state = nil
    end
end

local function refreshOverrideDispatchersForOwner(ownerId)
    for _, dispatcher in pairs(dispatchers.override) do
        if dispatcher.handlers and dispatcher.handlers[ownerId] then
            refreshOverrideDispatcher(dispatcher)
        end
    end
end

local function attachOwnerSlotsToDispatcher(dispatcher, ownerId, owner, pathHooks)
    addOwnerOrder(dispatcher, ownerId)
    dispatcher.handlers[ownerId] = dispatcher.handlers[ownerId] or {}
    local ownerSlotsForObject = dispatcher.handlers[ownerId][owner]
    if not ownerSlotsForObject then
        ownerSlotsForObject = {
            order = {},
            slots = {},
        }
        dispatcher.handlers[ownerId][owner] = ownerSlotsForObject
    end
    for _, key in ipairs(pathHooks.order) do
        if ownerSlotsForObject.slots[key] == nil then
            ownerSlotsForObject.order[#ownerSlotsForObject.order + 1] = key
        end
        ownerSlotsForObject.slots[key] = pathHooks.slots[key]
    end
end

local function detachOwnerSlotsFromDispatcher(dispatcher, ownerId, owner, pathHooks)
    local byOwner = dispatcher.handlers[ownerId]
    if byOwner then
        local ownerSlotsForObject = byOwner[owner]
        if ownerSlotsForObject then
            for _, key in ipairs(pathHooks.order) do
                removeSlotKey(ownerSlotsForObject, key, pathHooks.slots[key])
            end
            if #ownerSlotsForObject.order == 0 then
                byOwner[owner] = nil
            end
        end
    end
end

local function detachOwnerSlots(kind, path, ownerId, owner, pathHooks)
    local dispatcher = getDispatcher(kind, path)
    detachOwnerSlotsFromDispatcher(dispatcher, ownerId, owner, pathHooks)
    if kind == "override" then
        refreshOverrideDispatcher(dispatcher)
    end
    pruneDispatcherOwner(dispatcher, ownerId)
    pruneDispatcher(kind, path, dispatcher)
end

local function attachOwner(ownerId, owner, declarations)
    for path, pathHooks in pairs(declarations.wrap) do
        local dispatcher = getDispatcher("wrap", path)
        attachOwnerSlotsToDispatcher(dispatcher, ownerId, owner, pathHooks)
        ensureWrapDispatcher(dispatcher)
    end
    for path, pathHooks in pairs(declarations.contextWrap) do
        local dispatcher = getDispatcher("contextWrap", path)
        attachOwnerSlotsToDispatcher(dispatcher, ownerId, owner, pathHooks)
        ensureContextWrapDispatcher(dispatcher)
    end
    for path, pathHooks in pairs(declarations.override) do
        local dispatcher = getDispatcher("override", path)
        attachOwnerSlotsToDispatcher(dispatcher, ownerId, owner, pathHooks)
        addOwnerOrder(dispatcher, ownerId)
    end

    getOwnerSlot(ownerId).currentOwner = owner
    refreshOverrideDispatchersForOwner(ownerId)
end

local function detachOwner(ownerId, owner, declarations, previousCurrentOwner)
    local slot = getOwnerSlot(ownerId)
    if slot.currentOwner == owner then
        slot.currentOwner = previousCurrentOwner
    end

    for path, pathHooks in pairs(declarations.wrap) do
        detachOwnerSlots("wrap", path, ownerId, owner, pathHooks)
    end
    for path, pathHooks in pairs(declarations.contextWrap) do
        detachOwnerSlots("contextWrap", path, ownerId, owner, pathHooks)
    end
    for path, pathHooks in pairs(declarations.override) do
        detachOwnerSlots("override", path, ownerId, owner, pathHooks)
    end
    pruneOwnerSlot(ownerId)
end

return {
    getCurrentOwner = getCurrentOwner,
    createContextSurface = createContextSurface,
    attachOwner = attachOwner,
    detachOwner = detachOwner,
}
