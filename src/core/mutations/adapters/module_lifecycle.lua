local deps = ...

local logging = deps.logging
local moduleRegistry = deps.moduleRegistry
local lifecycle = deps.lifecycle

local moduleAdapter = {
    affectsRunData = lifecycle.affectsRunData,
}

local function requireHostRecord(host, apiName)
    local record = moduleRegistry.getRecord(host)
    if not record then
        logging.violate("mutation.invalid_registration", "%s: expected managed module record", apiName)
    end
    return record
end

local function getHostRecord(host, apiName)
    return requireHostRecord(host, apiName)
end

function moduleAdapter.applyForHost(host)
    local record = getHostRecord(host, "mutation.applyForHost")
    return lifecycle.apply(host.getHostId(), record.mutationBundle, record.runtime, record.host)
end

function moduleAdapter.syncForHost(host)
    local record = getHostRecord(host, "mutation.syncForHost")
    return lifecycle.sync(host.getHostId(), record.definition, record.mutationBundle, record.runtime, record.host)
end

function moduleAdapter.revertForHost(host)
    getHostRecord(host, "mutation.revertForHost")
    return lifecycle.revert(host.getHostId())
end

return moduleAdapter
