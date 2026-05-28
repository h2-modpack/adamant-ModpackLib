local deps = ...

local logging = deps.logging
local moduleRegistry = deps.moduleRegistry
local declarations = deps.declarations
local hostInstall = deps.hostInstall
local moduleAdapter = {}

local function requireModuleRecord(module, apiName)
    local record = moduleRegistry.getRecord(module)
    if not record then
        logging.violate("hooks.invalid_registration", "%s: expected managed module", apiName)
    end
    return record
end

function moduleAdapter.installForModule(module, declare)
    local record = requireModuleRecord(module, "hooks.installForModule")
    local ownerId = module.getHostId()
    local hookDeclarations
    if declare ~= nil then
        if type(declare) ~= "function" then
            logging.violate("hooks.invalid_registration", "hooks.installForModule: declare must be a function")
        end
        hookDeclarations = declarations.create()
        declare(declarations.createRegistrar(hookDeclarations, "hooks.installForModule"))
    else
        hookDeclarations = record.hookDeclarations or declarations.create()
    end
    return hostInstall.createReceipt(ownerId, module, hookDeclarations)
end

return moduleAdapter
