local deps = ...

local logging = deps.logging
local moduleRegistry = deps.moduleRegistry
local hooks = deps.hooks
local retained = deps.retained
local declarations = deps.declarations
local receipt = deps.receipt
local moduleAdapter = {}

local function requireModuleRecord(module, apiName)
    local record = moduleRegistry.getRecord(module)
    if not record then
        logging.violate("overlays.invalid_registration", "%s: expected managed module record", apiName)
    end
    return record
end

local function createAfterHookReceipt(module, paths)
    if #paths == 0 then
        return receipt.noop("overlays.afterHooks", receipt.PHASE_EFFECTS)
    end

    return hooks.installForModule(module, function(declare)
        for _, path in ipairs(paths) do
            local hookPath = path
            declare.wrap(hookPath, "overlay.after:" .. hookPath, function(base, ...)
                local args = table.pack(...)
                local results = table.pack(base(...))
                retained.dispatchAfterHook(module, hookPath, args, results)
                return table.unpack(results, 1, results.n)
            end)
        end
    end)
end

function moduleAdapter.installForModule(module)
    local record = requireModuleRecord(module, "overlays.installForModule")
    local ownerId = module.getOwnerId()
    if type(ownerId) ~= "string" or ownerId == "" then
        logging.violate("overlays.invalid_registration", "overlays.installForModule: module ownerId is required")
    end

    local stagingOwner = {}
    local pendingOwnerId = ownerId .. ":pending"
    local currentOwnerId = ownerId .. ":current"
    local transaction = retained.beginTransaction(stagingOwner)
    local afterHookReceipt = nil
    local overlayDeclarations = record.overlayDeclarations

    local ok, err = pcall(function()
        retained.refresh(stagingOwner, pendingOwnerId, record.host, record.runtime, function(registrar)
            declarations.replay(overlayDeclarations, registrar)
        end, { hidden = true })
        afterHookReceipt = createAfterHookReceipt(module, retained.getAfterHookPaths(stagingOwner))
    end)

    if not ok then
        transaction.rollback()
        error(err, 0)
    end

    -- Clears this module's promoted overlay elements, then releases the after-hook install
    -- through `releaseAfterHooks` (its rollback or retire).
    local function releaseCurrent(releaseAfterHooks)
        local clearTransaction = retained.beginTransaction(module)
        local clearOk, clearErr = pcall(function()
            retained.refresh(module, currentOwnerId, nil, nil, function() end)
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

    -- Rollback and retire both clear only this module's elements: commit discards the
    -- previous generation's elements outright, so there is no overlay state to restore.
    -- They differ only in how the after-hook install releases the hook owner slot.
    return receipt.create({
        name = "overlays",
        phase = receipt.PHASE_EFFECTS,
        commit = function()
            local hookOk, hookErr = afterHookReceipt.commit()
            if not hookOk then
                return false, hookErr
            end
            local clearOk, clearErr = retained.clearTableRegistriesByOwnerId(currentOwnerId, module)
            if not clearOk then
                return false, clearErr
            end
            transaction.commit()
            retained.promoteTableRegistry(stagingOwner, module, currentOwnerId, record.host, record.runtime)
            return true, nil
        end,
        rollback = function()
            return releaseCurrent(afterHookReceipt.rollback)
        end,
        retire = function()
            return releaseCurrent(afterHookReceipt.retire)
        end,
        -- Drops the hidden staging rows and any after-hook slots a failed commit attached.
        discard = function()
            transaction.rollback()
            return afterHookReceipt.rollback()
        end,
    })
end

return moduleAdapter
