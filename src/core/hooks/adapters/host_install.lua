local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local declarations = deps.declarations
local hostInstall = deps.hostInstall
local hostAdapter = {}

local function requireHostRecord(host, apiName)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("hooks.invalid_registration", "%s: expected managed module host", apiName)
    end
    return record
end

function hostAdapter.installForHost(host, declare)
    local record = requireHostRecord(host, "hooks.installForHost")
    local ownerId = host.getHostId()
    local hookDeclarations
    if declare ~= nil then
        if type(declare) ~= "function" then
            logging.violate("hooks.invalid_registration", "hooks.installForHost: declare must be a function")
        end
        hookDeclarations = declarations.create()
        declare(declarations.createRegistrar(hookDeclarations, "hooks.installForHost"))
    else
        hookDeclarations = record.hookDeclarations or declarations.create()
    end
    return hostInstall.createReceipt(ownerId, host, hookDeclarations)
end

return hostAdapter
