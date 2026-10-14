local deps = ...

local sharedRegistry = deps.sharedRegistry
local receipt = deps.receipt
sharedRegistry.events = sharedRegistry.events or {}
sharedRegistry.events.listeners = sharedRegistry.events.listeners or {}
sharedRegistry.data = sharedRegistry.data or {}

local eventRegistry = import('core/shared/events/registry.lua', nil, {
    eventRegistry = sharedRegistry.events,
})

local registrations = import('core/shared/events/registrations.lua', nil, {
    logging = deps.logging,
    registry = eventRegistry,
    receipt = receipt,
})

local events = import('core/shared/events/events.lua', nil, {
    logging = deps.logging,
    registry = eventRegistry,
})

local data = import('core/shared/data.lua', nil, {
    logging = deps.logging,
    values = deps.values,
    receipt = receipt,
    sharedRegistry = sharedRegistry.data,
})

local refs = import('core/shared/refs.lua', nil, {
    logging = deps.logging,
    data = data,
})

--- Installs one owner's shared data publications and event listeners as one receipt.
---@param ownerId string
---@param inputs { data: table, events: table }
---@return AdamantModpackLib.Receipt
local function install(ownerId, inputs)
    return receipt.composite("shared", receipt.PHASE_EFFECTS, {
        data.install(ownerId, inputs.data),
        registrations.install(ownerId, inputs.events),
    })
end

return {
    install = install,
    events = events,
    registrations = registrations,
    dataDeclarations = data,
    refs = refs,
}
