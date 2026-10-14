local deps = ...

local logging = deps.logging
local coordinator = deps.coordinator
local moduleRegistry = deps.moduleRegistry
-- Ordered `install(ownerId, owner, capabilityInputs) -> Receipt?` list composed by `core/init.lua`.
-- An install returns nil when the module declares nothing for that capability; the receipt's own
-- name identifies it in commit and release errors.
---@type AdamantModpackLib.ModuleCapabilityInstall[]
local capabilities = deps.capabilities

local moduleActivation = {}

local function warnReceiptRelease(warningId, warningPrefix, errors)
    if warningId == "managed_module.retire_failed" then
        logging.violate("managed_module.retire_failed", "%s: %s", warningPrefix, table.concat(errors, "; "))
    elseif warningId == "managed_module.activation_rollback_failed" then
        logging.violate("managed_module.activation_rollback_failed", "%s: %s", warningPrefix, table.concat(errors, "; "))
    end
end

-- Releases receipts in reverse commit order through `methodName` ("rollback" or "retire").
local function releaseReceipts(receipts, methodName, warningId, warningPrefix)
    local errors = {}
    for index = #receipts, 1, -1 do
        local receipt = receipts[index]
        local ok, err = receipt[methodName]()
        if not ok then
            errors[#errors + 1] = tostring(receipt.name) .. ": " .. tostring(err)
        end
    end
    if #errors > 0 then
        warnReceiptRelease(warningId, warningPrefix, errors)
    end
end

-- Stable order by receipt phase, so lower phases commit first and release last.
local function orderByPhase(receipts)
    local ordered = {}
    for index, receipt in ipairs(receipts) do
        ordered[index] = { receipt = receipt, index = index }
    end
    table.sort(ordered, function(left, right)
        if left.receipt.phase ~= right.receipt.phase then
            return left.receipt.phase < right.receipt.phase
        end
        return left.index < right.index
    end)
    for index, entry in ipairs(ordered) do
        ordered[index] = entry.receipt
    end
    return ordered
end

local function retireOldModule(previousModule, replacementLabel)
    local oldRecord = moduleRegistry.getRecord(previousModule)
    local receipts = oldRecord and oldRecord.effectReceipts or nil
    if type(receipts) ~= "table" or #receipts == 0 then
        return
    end
    -- Retire, not rollback: restoring what the old module replaced would resurrect an older generation.
    releaseReceipts(receipts, "retire", "managed_module.retire_failed",
        tostring(replacementLabel) .. " previous module retirement failed")
    oldRecord.effectReceipts = {}
end

function moduleActivation.activateOrThrow(module)
    local record = moduleRegistry.getRecord(module)
    if not record then
        logging.violate("managed_module.invalid_activate_opts", "module.activate: module is required")
    end

    local pluginGuid = module.getOwnerId()
    local def = record.definition

    if record.activated == true then
        logging.violate("managed_module.already_activated", "module.activate: module is already activated")
    end
    if record.activating == true then
        logging.violate("managed_module.activation_in_progress", "module.activate: module activation is already in progress")
    end
    local meta = module.getMeta()
    local moduleId = module.getModuleId()
    local packId = module.getPackId()
    local pendingCoordinatorRebuild = def._pendingCoordinatorRebuild
    local previousModule = moduleRegistry.getLiveModule(pluginGuid)
    local inputs = record.capabilityInputs
    local candidateReceipts = {}
    local published = false
    record.activating = true

    local ok, err = pcall(function()
        -- The module itself is the owner token (hooks and the overlay after-hook install share
        -- the module's hook slot).
        for _, install in ipairs(capabilities) do
            local capabilityReceipt = install(pluginGuid, module, inputs)
            if capabilityReceipt ~= nil then
                candidateReceipts[#candidateReceipts + 1] = capabilityReceipt
            end
        end
        -- Rollback and retirement walk this list in reverse, so commit order is release order.
        candidateReceipts = orderByPhase(candidateReceipts)

        for _, receipt in ipairs(candidateReceipts) do
            local commitOk, commitErr = receipt.commit()
            if not commitOk then
                error(tostring(receipt.name) .. " commit failed: " .. tostring(commitErr), 0)
            end
        end

        record.effectReceipts = candidateReceipts
        record.activating = false
        record.activated = true
        moduleRegistry.setLiveModule(pluginGuid, module)
        published = true

        if record.onActivate ~= nil then
            record.onActivate(record.host, record.runtime)
        end

        if pendingCoordinatorRebuild ~= nil then
            local requested = coordinator.requestRebuild(packId, pendingCoordinatorRebuild)
            if requested then
                def._pendingCoordinatorRebuild = nil
            else
                logging.violate(
                    "managed_module.structural_rebuild_unavailable",
                    "%s structural definition changed during hot reload; full reload required",
                    tostring(meta.name or moduleId or "module"))
            end
        end
    end)

    if not ok then
        record.activating = false
        record.activated = false
        record.effectReceipts = {}
        releaseReceipts(candidateReceipts, "rollback", "managed_module.activation_rollback_failed",
            tostring(meta.name or moduleId or "module") .. " activation rollback failed")
        if published then
            moduleRegistry.setLiveModule(pluginGuid, previousModule)
        end
        error(err, 0)
    end

    retireOldModule(previousModule, meta.name or moduleId or "module")
    return true, nil
end

function moduleActivation.activate(module)
    local ok, err = pcall(moduleActivation.activateOrThrow, module)
    if ok then
        return true, nil
    end

    err = tostring(err)
    logging.violate("managed_module.activate_failed", "module.activate failed; skipping module: %s", err)
    return false, err
end

return moduleActivation
