local deps = ...

local logging = deps.logging
local moduleRegistry = deps.moduleRegistry
local hooks = deps.hooks
local retained = deps.retained
local declarations = deps.declarations
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
        return nil
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

local function disposeReceipt(receipt)
    if not receipt then
        return true, nil
    end
    return receipt.dispose()
end

function moduleAdapter.installForModule(module, store)
    local record = requireModuleRecord(module, "overlays.installForModule")
    local ownerId = module.getHostId()
    if type(ownerId) ~= "string" or ownerId == "" then
        logging.violate("overlays.invalid_registration", "overlays.installForModule: module ownerId is required")
    end

    local stagingOwner = {}
    local pendingOwnerId = ownerId .. ":pending"
    local currentOwnerId = ownerId .. ":current"
    local transaction = retained.beginTransaction(stagingOwner)
    local afterHookReceipt = nil
    local afterHookReceiptCommitted = false
    local overlayDeclarations = record.overlayDeclarations
    local committed = false
    local disposed = false

    local ok, err = pcall(function()
        retained.refresh(stagingOwner, pendingOwnerId, module, store, function(registrar)
            declarations.replay(overlayDeclarations, registrar)
        end, { hidden = true })
        afterHookReceipt = createAfterHookReceipt(module, retained.getAfterHookPaths(stagingOwner))
    end)

    if not ok then
        transaction.rollback()
        error(err, 0)
    end

    return {
        commit = function()
            if disposed or committed then
                return true, nil
            end
            if afterHookReceipt then
                local hookOk, hookErr = afterHookReceipt.commit()
                if not hookOk then
                    return false, hookErr
                end
                afterHookReceiptCommitted = true
            end
            local clearOk, clearErr = retained.clearTableRegistriesByOwnerId(currentOwnerId, module)
            if not clearOk then
                if afterHookReceiptCommitted then
                    disposeReceipt(afterHookReceipt)
                    afterHookReceiptCommitted = false
                end
                return false, clearErr
            end
            transaction.commit()
            retained.promoteTableRegistry(stagingOwner, module, currentOwnerId, module, store)
            committed = true
            return true, nil
        end,
        dispose = function()
            if disposed then
                return true, nil
            end
            if not committed then
                transaction.rollback()
                if afterHookReceiptCommitted then
                    disposeReceipt(afterHookReceipt)
                    afterHookReceiptCommitted = false
                end
                disposed = true
                return true, nil
            end

            local disposeTransaction = retained.beginTransaction(module)
            local disposeOk, disposeErr = pcall(function()
                retained.refresh(module, currentOwnerId, nil, nil, function() end)
            end)
            local hookOk, hookErr = disposeReceipt(afterHookReceipt)
            afterHookReceiptCommitted = false
            if disposeOk then
                disposeTransaction.commit()
                disposed = true
                if not hookOk then
                    return false, hookErr
                end
                return true, nil
            end

            disposeTransaction.rollback()
            disposed = true
            return false, disposeErr
        end,
    }
end

return moduleAdapter
