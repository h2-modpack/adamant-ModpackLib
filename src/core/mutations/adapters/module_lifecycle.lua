local deps = ...

local logging = deps.logging
local moduleRegistry = deps.moduleRegistry
local lifecycle = deps.lifecycle

local moduleAdapter = {
    affectsRunData = lifecycle.affectsRunData,
}

local function requireModuleRecord(module, apiName)
    local record = moduleRegistry.getRecord(module)
    if not record then
        logging.violate("mutation.invalid_registration", "%s: expected managed module record", apiName)
    end
    return record
end

local function getModuleRecord(module, apiName)
    return requireModuleRecord(module, apiName)
end

function moduleAdapter.applyForModule(module)
    local record = getModuleRecord(module, "mutation.applyForModule")
    return lifecycle.apply(module.getOwnerId(), record.mutationBundle, record.runtime, record.host)
end

function moduleAdapter.syncForModule(module)
    local record = getModuleRecord(module, "mutation.syncForModule")
    return lifecycle.sync(module.getOwnerId(), record.definition, record.mutationBundle, record.runtime, record.host)
end

function moduleAdapter.revertForModule(module)
    getModuleRecord(module, "mutation.revertForModule")
    return lifecycle.revert(module.getOwnerId())
end

return moduleAdapter
