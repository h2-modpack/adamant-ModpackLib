local deps = ...

local hookRegistry = deps.hookRegistry
hookRegistry.ownerSlots = hookRegistry.ownerSlots or {}
hookRegistry.dispatchers = hookRegistry.dispatchers or {
    wrap = {},
    override = {},
    contextWrap = {},
}
hookRegistry.modutilOwnerKey = hookRegistry.modutilOwnerKey or "__adamantHooks"

local dispatchers = import('core/hooks/dispatchers.lua', nil, {
    modutil = deps.modutil,
    logging = deps.logging,
    hookRegistry = hookRegistry,
})

local declarations = import('core/hooks/declarations.lua', nil, {
    logging = deps.logging,
})

local hostInstall = import('core/hooks/host_install.lua', nil, {
    logging = deps.logging,
    dispatchers = dispatchers,
})

local hostAdapter = import('core/hooks/adapters/host_install.lua', nil, {
    logging = deps.logging,
    hostRegistry = deps.hostRegistry,
    declarations = declarations,
    hostInstall = hostInstall,
})

local author = import('core/hooks/adapters/author_declarations.lua', nil, {
    logging = deps.logging,
    hostRegistry = deps.hostRegistry,
    declarations = declarations,
})

local system = import('core/hooks/adapters/system_declarations.lua', nil, {
    logging = deps.logging,
    declarations = declarations,
    hostInstall = hostInstall,
})

local service = {
    installForHost = hostAdapter.installForHost,
}

return {
    service = service,
    author = author,
    system = system,
}
