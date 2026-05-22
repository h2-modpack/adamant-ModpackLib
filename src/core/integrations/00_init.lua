local deps = ...

local integrationRegistry = deps.integrationRegistry
integrationRegistry.providers = integrationRegistry.providers or {}

local registry = import('core/integrations/registry.lua', nil, {
    integrationRegistry = integrationRegistry,
})

local readScope = import('core/integrations/read_scope.lua', nil, {
    logging = deps.logging,
    storage = deps.storage,
})

local registrations = import('core/integrations/registrations.lua', nil, {
    logging = deps.logging,
    registry = registry,
    readScope = readScope,
})

local invocation = import('core/integrations/invocation.lua', nil, {
    logging = deps.logging,
    registry = registry,
})

local service = import('core/integrations/adapters/host_install.lua', nil, {
    logging = deps.logging,
    hostRegistry = deps.hostRegistry,
    registrations = registrations,
})

local author = import('core/integrations/adapters/author_integrations.lua', nil, {
    logging = deps.logging,
    hostRegistry = deps.hostRegistry,
    registrations = registrations,
    invocation = invocation,
})

return {
    service = service,
    author = author,
}
