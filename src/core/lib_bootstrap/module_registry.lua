local deps = ...

local modules = deps.moduleBucket

modules.live = modules.live or {}
modules.pluginInfo = modules.pluginInfo or {}
modules.pendingCoordinatorRebuilds = modules.pendingCoordinatorRebuilds
    or setmetatable({}, { __mode = "k" })
modules.records = modules.records or setmetatable({}, { __mode = "k" })

local liveModules = modules.live
local pluginInfo = modules.pluginInfo
local pendingCoordinatorRebuilds = modules.pendingCoordinatorRebuilds
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

function moduleRegistry.getPluginInfo(pluginGuid)
    return pluginInfo[pluginGuid]
end

function moduleRegistry.setPluginInfo(pluginGuid, info)
    pluginInfo[pluginGuid] = info
end

function moduleRegistry.getPendingCoordinatorRebuild(definition)
    return pendingCoordinatorRebuilds[definition]
end

function moduleRegistry.setPendingCoordinatorRebuild(definition, rebuild)
    pendingCoordinatorRebuilds[definition] = rebuild
end

return moduleRegistry
