local deps = ...

local hosts = deps.hostBucket

hosts.live = hosts.live or {}
hosts.pluginInfo = hosts.pluginInfo or {}
hosts.pendingCoordinatorRebuilds = hosts.pendingCoordinatorRebuilds
    or setmetatable({}, { __mode = "k" })
hosts.records = hosts.records or setmetatable({}, { __mode = "k" })

local liveHosts = hosts.live
local pluginInfo = hosts.pluginInfo
local pendingCoordinatorRebuilds = hosts.pendingCoordinatorRebuilds
local hostRecords = hosts.records

local hostRegistry = {}

function hostRegistry.getRecord(host)
    return hostRecords[host]
end

function hostRegistry.setRecord(host, record)
    hostRecords[host] = record
end

function hostRegistry.getLiveHost(pluginGuid)
    return liveHosts[pluginGuid]
end

function hostRegistry.setLiveHost(pluginGuid, host)
    liveHosts[pluginGuid] = host
end

function hostRegistry.getPluginInfo(pluginGuid)
    return pluginInfo[pluginGuid]
end

function hostRegistry.setPluginInfo(pluginGuid, info)
    pluginInfo[pluginGuid] = info
end

function hostRegistry.getPendingCoordinatorRebuild(definition)
    return pendingCoordinatorRebuilds[definition]
end

function hostRegistry.setPendingCoordinatorRebuild(definition, rebuild)
    pendingCoordinatorRebuilds[definition] = rebuild
end

return hostRegistry
