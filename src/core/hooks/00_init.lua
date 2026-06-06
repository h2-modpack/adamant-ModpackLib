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

local ownerInstall = import('core/hooks/owner_install.lua', nil, {
    logging = deps.logging,
    dispatchers = dispatchers,
})

local moduleAdapter = import('core/hooks/adapters/module_install.lua', nil, {
    logging = deps.logging,
    moduleRegistry = deps.moduleRegistry,
    declarations = declarations,
    ownerInstall = ownerInstall,
})

local system = import('core/hooks/adapters/system_declarations.lua', nil, {
    logging = deps.logging,
    declarations = declarations,
    ownerInstall = ownerInstall,
})

local service = {
    installForModule = moduleAdapter.installForModule,
}

return {
    service = service,
    declarations = declarations,
    context = {
        createSurface = dispatchers.createContextSurface,
    },
    system = system,
}
