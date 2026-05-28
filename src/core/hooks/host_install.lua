local deps = ...

local logging = deps.logging
local dispatchers = deps.dispatchers
local hostInstall = {}

function hostInstall.createReceipt(ownerId, owner, hookDeclarations)
    if type(ownerId) ~= "string" or ownerId == "" then
        logging.violate("hooks.invalid_registration", "hooks.installForModule: ownerId is required")
    end

    local install = {
        owner = owner,
        ownerId = ownerId,
        declarations = hookDeclarations,
        committed = false,
        slotsAttached = false,
        disposed = false,
        previousCurrentOwner = nil,
    }

    return {
        commit = function()
            if install.disposed or install.committed then
                return true, nil
            end

            install.previousCurrentOwner = dispatchers.getCurrentOwner(ownerId)
            install.slotsAttached = true
            dispatchers.attachOwner(ownerId, owner, install.declarations)
            install.committed = true
            return true, nil
        end,
        dispose = function()
            if install.disposed then
                return true, nil
            end

            if install.committed or install.slotsAttached then
                dispatchers.detachOwner(ownerId, owner, install.declarations, install.previousCurrentOwner)
            end

            install.slotsAttached = false
            install.disposed = true
            return true, nil
        end,
    }
end

return hostInstall
