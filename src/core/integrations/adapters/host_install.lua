local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local registrations = deps.registrations
local hostAdapter = {}

local function requireHostRecord(host, context)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("integrations.invalid_args", "%s: expected managed module host record", context)
    end
    return record
end

function hostAdapter.installForHost(host)
    local record = requireHostRecord(host, "integrations.installForHost")
    local ownerId = host.getHostId()
    return registrations.install(ownerId, record.integrationRegistrations)
end

return hostAdapter
