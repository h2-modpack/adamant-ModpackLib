local deps = ...

local logging = deps.logging
local registry = deps.registry
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

local function makeNoopReceipt()
    return {
        commit = function()
            return true, nil
        end,
        dispose = function()
            return true, nil
        end,
    }
end

local function ensureHostRegistrations(state)
    if not state.sharedEventRegistrations then
        state.sharedEventRegistrations = registrations.create()
    end
    return state.sharedEventRegistrations
end

local function createListener(hostProvider, callback)
    return {
        callback = callback,
        isEnabled = function()
            local host = hostProvider and hostProvider() or nil
            return host ~= nil and host.isEnabled() == true
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

function registrations.stageListener(registrationSet, hostProvider, id, eventName, callback)
    local context = "module.shared.listen"
    validateSharedId(context, id)
    validateEventName(context, eventName)
    if type(callback) ~= "function" then
        logging.violate("shared.invalid_args", "%s: callback must be a function", context)
    end
    return recordStagedListener(registrationSet, id, eventName, createListener(hostProvider, callback))
end

function registrations.stageAuthorListener(record, host, id, eventName, callback)
    return registrations.stageListener(ensureHostRegistrations(record), function()
        return host
    end, id, eventName, callback)
end

function registrations.install(ownerId, hostRegistrations)
    if not hasRegistrationEntries(hostRegistrations) then
        return makeNoopReceipt()
    end

    local install = {
        ownerId = ownerId,
        ownerToken = {},
        listenerEntries = {},
        previousListeners = {},
        committed = false,
        disposed = false,
    }

    for _, entry in ipairs(hostRegistrations.listenerEntries or {}) do
        recordStagedListener(install, entry.id, entry.eventName, entry.listener)
    end

    return {
        commit = function()
            if install.disposed or install.committed then
                return true, nil
            end
            for index, entry in ipairs(install.listenerEntries) do
                local key = ownerId .. "\0" .. tostring(index)
                local bucket = registry.getListenerBucket(entry.id, entry.eventName, false)
                install.previousListeners[index] = {
                    id = entry.id,
                    eventName = entry.eventName,
                    key = key,
                    existed = bucket and bucket.listeners[key] ~= nil or false,
                    listener = bucket and bucket.listeners[key] or nil,
                    ownerId = bucket and bucket.ownerIds[key] or nil,
                    ownerToken = bucket and bucket.ownerTokens[key] or nil,
                    orderIndex = bucket and registry.getListenerOrderIndex(bucket, key) or nil,
                }
                registry.setListener(entry.id, entry.eventName, key, entry.listener, ownerId, install.ownerToken)
            end
            install.committed = true
            return true, nil
        end,
        dispose = function()
            if install.disposed then
                return true, nil
            end
            if install.committed then
                for index = #install.listenerEntries, 1, -1 do
                    local previous = install.previousListeners[index]
                    local bucket = registry.getListenerBucket(
                        previous.id,
                        previous.eventName,
                        previous and previous.existed or false)
                    if bucket
                        and bucket.ownerIds[previous.key] == install.ownerId
                        and bucket.ownerTokens[previous.key] == install.ownerToken
                    then
                        if previous and previous.existed then
                            bucket.listeners[previous.key] = previous.listener
                            bucket.ownerIds[previous.key] = previous.ownerId
                            bucket.ownerTokens[previous.key] = previous.ownerToken
                            registry.insertListenerOrder(bucket, previous.key, previous.orderIndex)
                        else
                            registry.removeListenerFromBucket(
                                bucket,
                                previous.key,
                                install.ownerId,
                                install.ownerToken)
                            registry.pruneListenerBucket(previous.id, previous.eventName, bucket)
                        end
                    end
                end
            end
            install.disposed = true
            return true, nil
        end,
    }
end

return registrations
