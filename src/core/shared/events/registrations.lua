local deps = ...

local logging = deps.logging
local registry = deps.registry
local receipt = deps.receipt
local registrations = {}

local function validateSharedId(context, id)
    if type(id) ~= "string" or id == "" then
        logging.violate("shared.invalid_args", "%s: id must be a non-empty string", context)
    end
end

local function validateEventName(context, eventName)
    if type(eventName) ~= "string" or eventName == "" then
        logging.violate("shared.invalid_args", "%s: event name must be a non-empty string", context)
    end
end

local function createRegistrationSet()
    return {
        listenerEntries = {},
    }
end

local function hasRegistrationEntries(registrationSet)
    return registrationSet and #(registrationSet.listenerEntries or {}) > 0
end

local function ensureHostRegistrations(state)
    if not state.sharedEventRegistrations then
        state.sharedEventRegistrations = registrations.create()
    end
    return state.sharedEventRegistrations
end

local function createListener(getModule, callback)
    return {
        callback = callback,
        isEnabled = function()
            local module = getModule and getModule() or nil
            return module ~= nil and module.isEnabled() == true
        end,
    }
end

local function recordStagedListener(registrationSet, id, eventName, listener)
    registrationSet.listenerEntries = registrationSet.listenerEntries or {}
    registrationSet.listenerEntries[#registrationSet.listenerEntries + 1] = {
        id = id,
        eventName = eventName,
        listener = listener,
    }
    return listener
end

function registrations.create()
    return createRegistrationSet()
end

function registrations.stageListener(registrationSet, getModule, id, eventName, callback)
    local context = "module.shared.listen"
    validateSharedId(context, id)
    validateEventName(context, eventName)
    if type(callback) ~= "function" then
        logging.violate("shared.invalid_args", "%s: callback must be a function", context)
    end
    return recordStagedListener(registrationSet, id, eventName, createListener(getModule, callback))
end

function registrations.stageAuthorListener(record, host, id, eventName, callback)
    return registrations.stageListener(ensureHostRegistrations(record), function()
        return host
    end, id, eventName, callback)
end

function registrations.install(ownerId, hostRegistrations)
    if not hasRegistrationEntries(hostRegistrations) then
        return receipt.noop("shared.events", receipt.PHASE_EFFECTS)
    end

    local ownerToken = {}
    local install = {
        listenerEntries = {},
    }
    local previousListeners = {}

    for _, entry in ipairs(hostRegistrations.listenerEntries or {}) do
        recordStagedListener(install, entry.id, entry.eventName, entry.listener)
    end

    return receipt.create({
        name = "shared.events",
        phase = receipt.PHASE_EFFECTS,
        commit = function()
            for index, entry in ipairs(install.listenerEntries) do
                local key = ownerId .. "\0" .. tostring(index)
                local bucket = registry.getListenerBucket(entry.id, entry.eventName, false)
                previousListeners[index] = {
                    id = entry.id,
                    eventName = entry.eventName,
                    key = key,
                    existed = bucket and bucket.listeners[key] ~= nil or false,
                    listener = bucket and bucket.listeners[key] or nil,
                    ownerId = bucket and bucket.ownerIds[key] or nil,
                    ownerToken = bucket and bucket.ownerTokens[key] or nil,
                    orderIndex = bucket and registry.getListenerOrderIndex(bucket, key) or nil,
                }
                registry.setListener(entry.id, entry.eventName, key, entry.listener, ownerId, ownerToken)
            end
            return true, nil
        end,
        rollback = function()
            for index = #install.listenerEntries, 1, -1 do
                local previous = previousListeners[index]
                local bucket = registry.getListenerBucket(previous.id, previous.eventName, previous.existed)
                if bucket
                    and bucket.ownerIds[previous.key] == ownerId
                    and bucket.ownerTokens[previous.key] == ownerToken
                then
                    if previous.existed then
                        bucket.listeners[previous.key] = previous.listener
                        bucket.ownerIds[previous.key] = previous.ownerId
                        bucket.ownerTokens[previous.key] = previous.ownerToken
                        registry.insertListenerOrder(bucket, previous.key, previous.orderIndex)
                    else
                        registry.removeListenerFromBucket(bucket, previous.key, ownerId, ownerToken)
                        registry.pruneListenerBucket(previous.id, previous.eventName, bucket)
                    end
                end
            end
            return true, nil
        end,
        -- Retire never restores the listener it replaced, which belongs to a retired generation.
        retire = function()
            for index = #install.listenerEntries, 1, -1 do
                local previous = previousListeners[index]
                local bucket = registry.getListenerBucket(previous.id, previous.eventName, false)
                if registry.removeListenerFromBucket(bucket, previous.key, ownerId, ownerToken) then
                    registry.pruneListenerBucket(previous.id, previous.eventName, bucket)
                end
            end
            return true, nil
        end,
    })
end

return registrations
