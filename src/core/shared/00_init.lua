local deps = ...

local sharedRegistry = deps.sharedRegistry
sharedRegistry.events = sharedRegistry.events or {}
sharedRegistry.events.listeners = sharedRegistry.events.listeners or {}
sharedRegistry.data = sharedRegistry.data or {}

local eventRegistry = import('core/shared/events/registry.lua', nil, {
    eventRegistry = sharedRegistry.events,
})

local registrations = import('core/shared/events/registrations.lua', nil, {
    logging = deps.logging,
    registry = eventRegistry,
})

local events = import('core/shared/events/events.lua', nil, {
    logging = deps.logging,
    registry = eventRegistry,
})

local data = import('core/shared/data.lua', nil, {
    logging = deps.logging,
    values = deps.values,
    sharedRegistry = sharedRegistry.data,
})

local moduleInstall = import('core/shared/adapters/module_install.lua', nil, {
    logging = deps.logging,
    moduleRegistry = deps.moduleRegistry,
    registrations = registrations,
    data = data,
})

local service = {
    installForModule = moduleInstall.installForModule,
    data = data,
}

function service.emitForHost(host, id, eventName, payload)
    local record = deps.moduleRegistry.getRecord(host)
    if not record then
        deps.logging.violate("shared.invalid_args", "module.shared.emit: expected managed module record")
    end
    if record.activated ~= true then
        deps.logging.violate("shared.invalid_args", "module.shared.emit requires module.activate() before it can run")
    end
    if host.isEnabled() ~= true then
        return true, 0
    end
    return events.emit("module.shared.emit", id, eventName, payload)
end

local dataAdapter = import('core/shared/adapters/data_shared.lua', nil, {
    logging = deps.logging,
    phaseGate = deps.phaseGate,
    service = service,
})

return {
    service = service,
    registrations = registrations,
    data = dataAdapter,
    dataDeclarations = data,
}
