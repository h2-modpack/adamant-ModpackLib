local deps = ...

local integrationRegistry = deps.integrationRegistry
integrationRegistry.providers = integrationRegistry.providers or {}
integrationRegistry.listeners = integrationRegistry.listeners or {}

local constants = import('core/integrations/events/constants.lua')

local registry = import('core/integrations/registry.lua', nil, {
    integrationRegistry = integrationRegistry,
})

local readScope = import('core/integrations/polling/read_scope.lua', nil, {
    logging = deps.logging,
    storage = deps.storage,
})

local registrations = import('core/integrations/registrations.lua', nil, {
    logging = deps.logging,
    registry = registry,
    readScope = readScope,
    constants = constants,
})

local polling = import('core/integrations/polling/polling.lua', nil, {
    logging = deps.logging,
    registry = registry,
})

local events = import('core/integrations/events/events.lua', nil, {
    logging = deps.logging,
    registry = registry,
    constants = constants,
})

local service = import('core/integrations/adapters/host_install.lua', nil, {
    logging = deps.logging,
    hostRegistry = deps.hostRegistry,
    registrations = registrations,
    events = events,
})

local author = import('core/integrations/adapters/author_integrations.lua', nil, {
    logging = deps.logging,
    hostRegistry = deps.hostRegistry,
    registrations = registrations,
    polling = polling,
    events = events,
})

return {
    service = service,
    author = author,
}
