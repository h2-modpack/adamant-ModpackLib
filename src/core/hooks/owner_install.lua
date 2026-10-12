local deps = ...

local logging = deps.logging
local dispatchers = deps.dispatchers
local receipt = deps.receipt
local ownerInstall = {}

function ownerInstall.createReceipt(ownerId, owner, hookDeclarations)
    if type(ownerId) ~= "string" or ownerId == "" then
        logging.violate("hooks.invalid_registration", "hooks.installForModule: ownerId is required")
    end

    local attempted = false
    local previousCurrentOwner = nil

    -- Rollback hands the owner slot back to the owner this install displaced.
    local function rollback()
        dispatchers.detachOwner(ownerId, owner, hookDeclarations, previousCurrentOwner)
        return true, nil
    end

    return receipt.create({
        name = "hooks",
        phase = receipt.PHASE_EFFECTS,
        commit = function()
            attempted = true
            previousCurrentOwner = dispatchers.getCurrentOwner(ownerId)
            dispatchers.attachOwner(ownerId, owner, hookDeclarations)
            return true, nil
        end,
        rollback = rollback,
        -- Retire never restores the displaced owner: after a reload that owner is a dead
        -- generation. A successor's attach already moved the slot off this owner.
        retire = function()
            dispatchers.detachOwner(ownerId, owner, hookDeclarations, nil)
            return true, nil
        end,
        -- A failed attach may have left slots behind; detach them like a rollback.
        discard = function()
            if attempted then
                return rollback()
            end
            return true, nil
        end,
    })
end

return ownerInstall
