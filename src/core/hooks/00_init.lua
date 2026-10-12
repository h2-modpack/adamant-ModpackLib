local deps = ...

local hookRegistry = deps.hookRegistry
hookRegistry.ownerSlots = hookRegistry.ownerSlots or {}
hookRegistry.dispatchers = hookRegistry.dispatchers or {
    wrap = {},
    override = {},
    contextWrap = {},
}
-- Active system hook receipts by owner id; anchored so a Lib re-import can retire
-- the previous import's system install instead of leaving its handlers attached.
hookRegistry.systemReceipts = hookRegistry.systemReceipts or {}

local dispatchers = import('core/hooks/dispatchers.lua', nil, {
    modutil = deps.modutil,
    logging = deps.logging,
    hookRegistry = hookRegistry,
})

local declarations = import('core/hooks/declarations.lua', nil, {
    logging = deps.logging,
})

local ownerInstall = import('core/hooks/owner_install.lua', nil, {
    dispatchers = dispatchers,
    receipt = deps.receipt,
})

local system = import('core/hooks/adapters/system_declarations.lua', nil, {
    logging = deps.logging,
    declarations = declarations,
    ownerInstall = ownerInstall,
    activeReceipts = hookRegistry.systemReceipts,
})

local service = {
    install = ownerInstall.install,
}

return {
    service = service,
    declarations = declarations,
    context = {
        createSurface = dispatchers.createContextSurface,
    },
    system = system,
}
