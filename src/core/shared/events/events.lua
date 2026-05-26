local deps = ...

local logging = deps.logging
local registry = deps.registry
local events = {}

local MAX_DRAINED_EVENTS = 1000
local queue = {}
local delivering = false

local function validateSharedId(context, id)
    if type(id) ~= "string" or id == "" then
        logging.violate("shared.invalid_args", "%s: id must be a non-empty string", context)
    end
end

local function validateEventName(context, eventName)
    if type(eventName) ~= "string" or eventName == "" then
        logging.violate("shared.invalid_args", "%s: eventName must be a non-empty string", context)
    end
end

local function isEnabled(record)
    return record.isEnabled == nil or record.isEnabled() ~= false
end

local function enqueueEvent(id, eventName, payload)
    queue[#queue + 1] = {
        id = id,
        eventName = eventName,
        payload = payload,
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
            local ok, err = pcall(listener.callback, item.payload)
            if not ok then
                logging.violate(
                    "shared.listener_failed",
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
                "shared.event_cycle",
                "shared event queue exceeded %s events; dropping remaining queued events",
                tostring(MAX_DRAINED_EVENTS))
            break
        end

        local item = table.remove(queue, 1)
        delivered = delivered + deliverQueuedEvent(item)
    end
    return delivered
end

function events.emit(context, id, eventName, payload)
    validateSharedId(context, id)
    validateEventName(context, eventName)

    enqueueEvent(id, eventName, payload)

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
