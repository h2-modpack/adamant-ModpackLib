local deps = ...

local logging = deps.logging
local moduleRegistry = deps.moduleRegistry
local registrations = deps.registrations
local data = deps.data
local receipt = deps.receipt
local moduleAdapter = {}

local function requireModuleRecord(module, context)
    local record = moduleRegistry.getRecord(module)
    if not record then
        logging.violate("shared.invalid_args", "%s: expected managed module record", context)
    end
    return record
end

function moduleAdapter.installForModule(module)
    local record = requireModuleRecord(module, "shared.installForModule")
    local ownerId = module.getOwnerId()
    return receipt.composite("shared", receipt.PHASE_EFFECTS, {
        data.install(ownerId, record.sharedDataDeclarations),
        registrations.install(ownerId, record.sharedEventRegistrations),
    })
end

return moduleAdapter
