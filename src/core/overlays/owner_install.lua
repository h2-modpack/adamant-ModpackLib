local deps = ...

local hooks = deps.hooks
local hookDeclarations = deps.hookDeclarations
local retained = deps.retained
local declarations = deps.declarations
local receipt = deps.receipt
local ownerInstall = {}

-- After-hook projections install through the hooks capability under the same owner token as
-- the owner's own hooks, so they share (and follow) that owner's hook slot.
local function createAfterHookReceipt(ownerId, owner, paths)
    if #paths == 0 then
        return receipt.noop("overlays.afterHooks", receipt.PHASE_EFFECTS)
    end

    local afterHooks = hookDeclarations.create()
    local declare = hookDeclarations.createRegistrar(afterHooks, "overlays.afterHook")
    for _, path in ipairs(paths) do
        local hookPath = path
        declare.wrap(hookPath, "overlay.after:" .. hookPath, function(base, ...)
            local args = table.pack(...)
            local results = table.pack(base(...))
            retained.dispatchAfterHook(owner, hookPath, args, results)
            return table.unpack(results, 1, results.n)
        end)
    end
    return hooks.install(ownerId, owner, afterHooks)
end

--- Installs one owner's declared overlays. `owner` is the owner token: it keys the retained
--- registry (and commit/after-hook dispatch) and the after-hook install's hook slot.
---@param ownerId string
---@param inputs { owner: table, declarations: table?, host: AdamantModpackLib.Host, runtime: AdamantModpackLib.RuntimeContext }
---@return AdamantModpackLib.Receipt
function ownerInstall.install(ownerId, inputs)
    local owner = inputs.owner
    local host = inputs.host
    local runtime = inputs.runtime

    local stagingOwner = {}
    local pendingOwnerId = ownerId .. ":pending"
    local currentOwnerId = ownerId .. ":current"
    local transaction = retained.beginTransaction(stagingOwner)
    local afterHookReceipt = nil
    -- Previous generations' registries this install's commit cleared; rollback reinstates them.
    local clearedPrevious = {}

    local ok, err = pcall(function()
        retained.refresh(stagingOwner, pendingOwnerId, host, runtime, function(registrar)
            declarations.replay(inputs.declarations, registrar)
        end, { hidden = true })
        afterHookReceipt = createAfterHookReceipt(ownerId, owner, retained.getAfterHookPaths(stagingOwner))
    end)

    if not ok then
        transaction.rollback()
        error(err, 0)
    end

    -- Clears this owner's promoted overlay elements, then releases the after-hook install
    -- through `releaseAfterHooks` (its rollback or retire).
    local function releaseCurrent(releaseAfterHooks)
        local clearTransaction = retained.beginTransaction(owner)
        local clearOk, clearErr = pcall(function()
            retained.refresh(owner, currentOwnerId, nil, nil, function() end)
        end)
        if clearOk then
            clearTransaction.commit()
        else
            clearTransaction.rollback()
        end
        local hookOk, hookErr = releaseAfterHooks()
        if not clearOk then
            return false, clearErr
        end
        return hookOk, hookErr
    end

    local function restorePrevious()
        retained.restoreTableRegistries(clearedPrevious)
        clearedPrevious = {}
    end

    -- Commit clears the previous generation's elements. Rollback clears this owner's elements
    -- and reinstates the previous generation's; retire only clears this owner's elements,
    -- since the previous generation is dead by then.
    return receipt.create({
        name = "overlays",
        phase = receipt.PHASE_EFFECTS,
        commit = function()
            local hookOk, hookErr = afterHookReceipt.commit()
            if not hookOk then
                return false, hookErr
            end
            local clearOk, clearErr, cleared = retained.clearTableRegistriesByOwnerId(currentOwnerId, owner)
            clearedPrevious = cleared
            if not clearOk then
                return false, clearErr
            end
            transaction.commit()
            retained.promoteTableRegistry(stagingOwner, owner, currentOwnerId, host, runtime)
            return true, nil
        end,
        rollback = function()
            local releaseOk, releaseErr = releaseCurrent(afterHookReceipt.rollback)
            restorePrevious()
            return releaseOk, releaseErr
        end,
        retire = function()
            return releaseCurrent(afterHookReceipt.retire)
        end,
        -- Drops the hidden staging rows, any previous registries a failed commit cleared,
        -- and any after-hook slots it attached.
        discard = function()
            transaction.rollback()
            restorePrevious()
            return afterHookReceipt.rollback()
        end,
    })
end

return ownerInstall
