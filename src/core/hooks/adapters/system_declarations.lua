local deps = ...

local logging = deps.logging
local declarations = deps.declarations
local hostInstall = deps.hostInstall

local systemAdapter = {}
local activeReceipts = {}

local function commitReceipt(receipt)
    local ok, err = receipt.commit()
    if not ok then
        error(err, 0)
    end
end

local function define(systemScope, ownerId, register)
    if type(register) ~= "function" then
        logging.violate("hooks.invalid_registration", "system.hooks.define: register must be a function")
    end

    local hookDeclarations = declarations.create()
    register(declarations.createRegistrar(hookDeclarations, "system.hooks.define"))

    local previous = activeReceipts[ownerId]
    local receipt = hostInstall.createReceipt(ownerId, systemScope, hookDeclarations)
    if previous and previous.systemScope == systemScope then
        previous.receipt.dispose()
        activeReceipts[ownerId] = nil
        commitReceipt(receipt)
    else
        commitReceipt(receipt)
        if previous then
            previous.receipt.dispose()
        end
    end

    activeReceipts[ownerId] = {
        systemScope = systemScope,
        receipt = receipt,
    }
    return true
end

function systemAdapter.create(systemScope, ownerId)
    return {
        define = function(register)
            return define(systemScope, ownerId, register)
        end,
    }
end

return systemAdapter
