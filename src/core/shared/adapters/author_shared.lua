local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local registrations = deps.registrations
local events = deps.events
local data = deps.data
local author = {}

local function requireHostRecord(host, context)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("shared.invalid_args", "%s: expected managed module host record", context)
    end
    return record
end

local function requireRegistrationOpen(host, context, verb)
    local record = requireHostRecord(host, context)
    if record.activated == true or record.activating == true then
        logging.violate(
            "shared.invalid_args",
            "%s: cannot %s after activation begins",
            context,
            verb
        )
    end
    return record
end

local function requireActivated(host, context)
    local record = requireHostRecord(host, context)
    if record.activated ~= true then
        logging.violate("shared.invalid_args", "%s requires host.activate() before it can run", context)
    end
    return record
end

function author.create(host)
    return {
        data = {
            owner = function(name, opts)
                return data.stageOwner(
                    requireRegistrationOpen(host, "host.shared.data.owner", "declare shared data"),
                    host,
                    name,
                    opts)
            end,
            reader = function(name, opts)
                return data.stageReader(
                    requireRegistrationOpen(host, "host.shared.data.reader", "declare shared data"),
                    host,
                    name,
                    opts)
            end,
        },
        listen = function(id, eventName, callback)
            return registrations.stageAuthorListener(
                requireRegistrationOpen(host, "host.shared.listen", "listen"),
                host,
                id,
                eventName,
                callback)
        end,
        emit = function(id, eventName, payload)
            requireActivated(host, "host.shared.emit")
            if host.isEnabled() ~= true then
                return true, 0
            end
            return events.emit("host.shared.emit", id, eventName, payload)
        end,
    }
end

return author
