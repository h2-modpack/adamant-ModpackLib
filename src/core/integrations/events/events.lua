local deps = ...

local logging = deps.logging
local registry = deps.registry
local constants = deps.constants
local events = {}

local MAX_DRAINED_EVENTS = 1000
local queue = {}
local delivering = false

local function validateIntegrationId(context, id)
    if type(id) ~= "string" or id == "" then
        logging.violate("integrations.invalid_args", "%s: id must be a non-empty string", context)
    end
end

local function validateEventName(context, eventName)
    if type(eventName) ~= "string" or eventName == "" then
        logging.violate("integrations.invalid_args", "%s: eventName must be a non-empty string", context)
    end
end

local function isEnabled(record)
    return record.isEnabled == nil or record.isEnabled() ~= false
end

local function getEmitterProvider(context, host, id, eventName)
    if eventName == constants.PROVIDER_CHANGED_EVENT then
        logging.violate(
            "integrations.invalid_args",
            "%s: event '%s' is reserved by Lib",
            context,
            tostring(eventName))
    end
    local ownerId = host.getHostId()
    local provider, providerId = registry.getProviderForOwner(id, ownerId, isEnabled)
    if provider == nil then
        return nil, nil
    end
    if not provider.events or provider.events[eventName] ~= true then
        logging.violate(
            "integrations.undeclared_event",
            "%s: provider '%s' did not declare event '%s'",
            context,
            tostring(providerId),
            tostring(eventName))
    end
    return provider, providerId
end

local function enqueueEvent(id, eventName, payload, providerId)
    queue[#queue + 1] = {
        id = id,
        eventName = eventName,
        payload = payload,
        providerId = providerId,
    }
end

local function deliverQueuedEvent(item)
    local bucket = registry.getListenerBucket(item.id, item.eventName, false)
    if not bucket then
        return 0
    end

    local delivered = 0
    for _, key in ipairs(bucket.order) do
        local listener = bucket.listeners[key]
        if listener and isEnabled(listener) then
            delivered = delivered + 1
            local ok, err = pcall(listener.callback, item.payload, item.providerId)
            if not ok then
                logging.violate(
                    "integrations.listener_failed",
                    "%s.%s listener failed: %s",
                    tostring(item.id),
                    tostring(item.eventName),
                    tostring(err))
            end
        end
    end
    return delivered
end

local function drainQueue()
    local delivered = 0
    local drained = 0
    while #queue > 0 do
        drained = drained + 1
        if drained > MAX_DRAINED_EVENTS then
            queue = {}
            logging.violate(
                "integrations.event_cycle",
                "integration event queue exceeded %s events; dropping remaining queued events",
                tostring(MAX_DRAINED_EVENTS))
            break
        end

        local item = table.remove(queue, 1)
        delivered = delivered + deliverQueuedEvent(item)
    end
    return delivered
end

function events.emit(context, host, id, eventName, payload)
    validateIntegrationId(context, id)
    validateEventName(context, eventName)

    local _, providerId = getEmitterProvider(context, host, id, eventName)
    if providerId == nil then
        return false, "no enabled provider"
    end

    enqueueEvent(id, eventName, payload, providerId)

    if delivering then
        return true, 0
    end

    delivering = true
    local ok, deliveredOrErr = pcall(drainQueue)
    delivering = false
    if not ok then
        error(deliveredOrErr, 0)
    end
    return true, deliveredOrErr
end

function events.notifyProviderChangedForHost(host, enabled)
    local ownerId = host.getHostId()
    local providers = registry.listProvidersForOwner(ownerId)
    if #providers == 0 then
        return true, 0
    end

    local payload = {
        enabled = enabled == true,
    }
    for _, entry in ipairs(providers) do
        enqueueEvent(entry.id, constants.PROVIDER_CHANGED_EVENT, payload, entry.providerId)
    end

    if delivering then
        return true, 0
    end

    delivering = true
    local ok, deliveredOrErr = pcall(drainQueue)
    delivering = false
    if not ok then
        error(deliveredOrErr, 0)
    end
    return true, deliveredOrErr
end

return events
