local deps = ...

local modules = deps.moduleBucket

modules.live = modules.live or {}
modules.records = modules.records or setmetatable({}, { __mode = "k" })

local liveModules = modules.live
local moduleRecords = modules.records

local moduleRegistry = {}

function moduleRegistry.getRecord(module)
    return moduleRecords[module]
end

function moduleRegistry.setRecord(module, record)
    moduleRecords[module] = record
end

function moduleRegistry.getLiveModule(pluginGuid)
    return liveModules[pluginGuid]
end

function moduleRegistry.setLiveModule(pluginGuid, module)
    liveModules[pluginGuid] = module
end

return moduleRegistry
