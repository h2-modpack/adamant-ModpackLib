local deps = ...

local dispatchers = deps.dispatchers
local receipt = deps.receipt
local ownerInstall = {}

--- Installs `hookDeclarations` under `ownerId`, attached to the `owner` token. Installs that
--- share an owner token share that owner's slot: the slot follows the token, not the install.
---@param ownerId string
---@param owner table Owner token identifying this generation in the owner slot.
---@param hookDeclarations table Prepared hook declarations.
---@return AdamantModpackLib.Receipt
function ownerInstall.install(ownerId, owner, hookDeclarations)
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
