local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local registrations = deps.registrations
local invocation = deps.invocation
local author = {}

local function requireHostRecord(host, context)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("integrations.invalid_args", "%s: expected managed module host record", context)
    end
    return record
end

local function requireRegistrationOpen(host)
    local record = requireHostRecord(host, "host.integrations.register")
    if record.activated == true or record.activating == true then
        logging.violate(
            "integrations.invalid_args",
            "host.integrations.register: cannot register after activation begins"
        )
    end
    return record
end

function author.create(host)
    return {
        register = function(id, opts)
            return registrations.stageAuthorRegistration(requireRegistrationOpen(host), id, opts)
        end,
        invoke = function(id, methodName, fallback, ...)
            requireHostRecord(host, "host.integrations.invoke")
            return invocation.invoke("host.integrations.invoke", id, methodName, fallback, ...)
        end,
    }
end

return author
