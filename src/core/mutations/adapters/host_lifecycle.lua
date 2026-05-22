local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local lifecycle = deps.lifecycle

local hostAdapter = {
    affectsRunData = lifecycle.affectsRunData,
}

local function requireHostRecord(host, apiName)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("mutation.invalid_registration", "%s: expected managed module host record", apiName)
    end
    return record
end

local function getHostRecord(host, apiName)
    return requireHostRecord(host, apiName)
end

function hostAdapter.applyForHost(host)
    local record = getHostRecord(host, "mutation.applyForHost")
    return lifecycle.apply(host.getHostId(), record.mutationBundle, record.authorHost, record.store)
end

function hostAdapter.syncForHost(host)
    local record = getHostRecord(host, "mutation.syncForHost")
    return lifecycle.sync(host.getHostId(), record.definition, record.mutationBundle, record.authorHost, record.store)
end

function hostAdapter.revertForHost(host)
    getHostRecord(host, "mutation.revertForHost")
    return lifecycle.revert(host.getHostId())
end

return hostAdapter
