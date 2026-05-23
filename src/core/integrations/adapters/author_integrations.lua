local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local registrations = deps.registrations
local polling = deps.polling
local events = deps.events
local author = {}

local function requireHostRecord(host, context)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("integrations.invalid_args", "%s: expected managed module host record", context)
    end
    return record
end

local function requireRegistrationOpen(host, context, verb)
    local record = requireHostRecord(host, context)
    if record.activated == true or record.activating == true then
        logging.violate(
            "integrations.invalid_args",
            "%s: cannot %s after activation begins",
            context,
            verb
        )
    end
    return record
end

function author.create(host)
    return {
        provide = function(id, opts)
            return registrations.stageAuthorRegistration(
                requireRegistrationOpen(host, "host.integrations.provide", "provide"),
                host,
                id,
                opts)
        end,
        listen = function(id, eventName, callback)
            return registrations.stageAuthorListener(
                requireRegistrationOpen(host, "host.integrations.listen", "listen"),
                host,
                id,
                eventName,
                callback)
        end,
        emit = function(id, eventName, payload)
            requireHostRecord(host, "host.integrations.emit")
            return events.emit("host.integrations.emit", host, id, eventName, payload)
        end,
        poll = function(id, methodName, fallback, ...)
            requireHostRecord(host, "host.integrations.poll")
            return polling.poll("host.integrations.poll", id, methodName, fallback, ...)
        end,
    }
end

return author
