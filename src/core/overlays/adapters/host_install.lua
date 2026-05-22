local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local hooks = deps.hooks
local retained = deps.retained
local declarations = deps.declarations
local hostAdapter = {}

local function requireHostRecord(host, apiName)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("overlays.invalid_registration", "%s: expected managed module host record", apiName)
    end
    return record
end

local function createAfterHookReceipt(host, paths)
    if #paths == 0 then
        return nil
    end

    return hooks.installForHost(host, function(declare)
        for _, path in ipairs(paths) do
            local hookPath = path
            declare.wrap(hookPath, "overlay.after:" .. hookPath, function(base, ...)
                local args = { ... }
                local results = { base(...) }
                retained.dispatchAfterHook(host, hookPath, args, results)
                return table.unpack(results)
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

function hostAdapter.installForHost(host, authorHost, store)
    local record = requireHostRecord(host, "overlays.installForHost")
    local ownerId = host.getHostId()
    if type(ownerId) ~= "string" or ownerId == "" then
        logging.violate("overlays.invalid_registration", "overlays.installForHost: host ownerId is required")
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
        retained.refresh(stagingOwner, pendingOwnerId, authorHost, store, function(registrar)
            declarations.replay(overlayDeclarations, registrar)
        end, { hidden = true })
        afterHookReceipt = createAfterHookReceipt(host, retained.getAfterHookPaths(stagingOwner))
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
            local clearOk, clearErr = retained.clearTableRegistriesByOwnerId(currentOwnerId, host)
            if not clearOk then
                if afterHookReceiptCommitted then
                    disposeReceipt(afterHookReceipt)
                    afterHookReceiptCommitted = false
                end
                return false, clearErr
            end
            transaction.commit()
            retained.promoteTableRegistry(stagingOwner, host, currentOwnerId, authorHost, store)
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

            local disposeTransaction = retained.beginTransaction(host)
            local disposeOk, disposeErr = pcall(function()
                retained.refresh(host, currentOwnerId, nil, nil, function() end)
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

return hostAdapter
