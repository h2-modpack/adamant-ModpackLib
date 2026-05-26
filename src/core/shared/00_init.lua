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

local hostInstall = import('core/shared/adapters/host_install.lua', nil, {
    logging = deps.logging,
    hostRegistry = deps.hostRegistry,
    registrations = registrations,
    data = data,
})

local service = {
    installForHost = hostInstall.installForHost,
    data = data,
}

local author = import('core/shared/adapters/author_shared.lua', nil, {
    logging = deps.logging,
    hostRegistry = deps.hostRegistry,
    registrations = registrations,
    events = events,
    data = data,
})

local dataAdapter = import('core/shared/adapters/data_shared.lua', nil, {
    logging = deps.logging,
    phaseGate = deps.phaseGate,
    service = service,
})

return {
    service = service,
    author = author,
    data = dataAdapter,
}
