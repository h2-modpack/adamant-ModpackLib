local deps = ...

local logging = deps.logging
local shared = deps.shared
local hooks = deps.hooks
local overlays = deps.overlays
local mutation = deps.mutation
local fallbackUi = deps.fallbackUi
local coordinator = deps.coordinator
local moduleRegistry = deps.moduleRegistry

local moduleActivation = {}

local function createPluginInfo(pluginGuid, def)
    return {
        pluginGuid = pluginGuid,
        packId = def.modpack,
        moduleId = def.id,
        name = def.name,
    }
end

local function callReceipt(receipt, methodName)
    if not (receipt and type(receipt[methodName]) == "function") then
        return true, nil
    end

    local ok, result, err = pcall(receipt[methodName])
    if not ok then
        return false, result
    end
    if result == false then
        return false, err
    end
    return true, nil
end

local function warnReceiptDisposal(warningId, warningPrefix, errors)
    if warningId == "managed_module.retire_failed" then
        logging.violate("managed_module.retire_failed", "%s: %s", warningPrefix, table.concat(errors, "; "))
    elseif warningId == "managed_module.activation_rollback_failed" then
        logging.violate("managed_module.activation_rollback_failed", "%s: %s", warningPrefix, table.concat(errors, "; "))
    end
end

local function disposeReceipts(receipts, warningId, warningPrefix)
    local errors = {}
    for index = #receipts, 1, -1 do
        local entry = receipts[index]
        local ok, err = callReceipt(entry.receipt, "dispose")
        if not ok then
            errors[#errors + 1] = tostring(entry.name or "receipt") .. ": " .. tostring(err)
        end
    end
    if #errors > 0 then
        warnReceiptDisposal(warningId, warningPrefix, errors)
    end
    return errors
end

local function commitReceipt(entry)
    local ok, err = callReceipt(entry.receipt, "commit")
    if not ok then
        return false, tostring(entry.name or "receipt") .. " commit failed: " .. tostring(err)
    end
    return true, nil
end

local function retireOldModule(previousModule, replacementLabel)
    local oldRecord = moduleRegistry.getRecord(previousModule)
    local receipts = oldRecord and oldRecord.effectReceipts or nil
    if type(receipts) ~= "table" or #receipts == 0 then
        return
    end
    disposeReceipts(receipts, "managed_module.retire_failed", tostring(replacementLabel) .. " previous module retirement failed")
    oldRecord.effectReceipts = {}
end

--- Activates a constructed managed module by registering external side effects.
---@param module ManagedModule
function moduleActivation.activateOrThrow(module)
    local record = moduleRegistry.getRecord(module)
    if not record then
        logging.violate("managed_module.invalid_activate_opts", "managedModule.activateOrThrow: module is required")
    end

    local pluginGuid = module.getOwnerId()
    local store = record.store
    local def = record.definition

    if record.activated == true then
        logging.violate("managed_module.already_activated", "managedModule.activateOrThrow: module is already activated")
    end
    if record.activating == true then
        logging.violate("managed_module.activation_in_progress", "managedModule.activateOrThrow: module activation is already in progress")
    end
    local meta = module.getMeta()
    local moduleId = module.getModuleId()
    local packId = module.getPackId()
    local pendingCoordinatorRebuild = moduleRegistry.getPendingCoordinatorRebuild(def)
    local hasPendingCoordinatorRebuild = pendingCoordinatorRebuild ~= nil
    local previousModule = moduleRegistry.getLiveModule(pluginGuid)
    local previousPluginInfo = moduleRegistry.getPluginInfo(pluginGuid)
    local candidateReceipts = {}
    local retireReceipts = {}
    local published = false
    record.activating = true

    local function addReceipt(name, receipt, retire)
        local entry = {
            name = name,
            receipt = receipt,
        }
        candidateReceipts[#candidateReceipts + 1] = entry
        if retire == true then
            retireReceipts[#retireReceipts + 1] = entry
        end
        return entry
    end

    local ok, err = pcall(function()
        addReceipt("shared", shared.installForModule(module), true)
        addReceipt("hooks", hooks.installForModule(module), true)
        addReceipt("overlays", overlays.installForModule(module, store), true)
        addReceipt("mutation", mutation.syncForModule(module), false)
        if record.fallbackUiRequested == true then
            addReceipt("fallbackUi", fallbackUi.installForModule(module), true)
        end

        for _, entry in ipairs(candidateReceipts) do
            if entry.name == "mutation" then
                local commitOk, commitErr = commitReceipt(entry)
                if not commitOk then
                    error(commitErr, 0)
                end
            end
        end

        for _, entry in ipairs(candidateReceipts) do
            if entry.name ~= "mutation" then
                local commitOk, commitErr = commitReceipt(entry)
                if not commitOk then
                    error(commitErr, 0)
                end
            end
        end

        record.effectReceipts = retireReceipts
        record.activating = false
        record.activated = true
        moduleRegistry.setLiveModule(pluginGuid, module)
        moduleRegistry.setPluginInfo(pluginGuid, createPluginInfo(pluginGuid, def))
        published = true

        if type(record.onActivate) == "function" then
            record.onActivate(record.host, record.runtime)
        end

        if hasPendingCoordinatorRebuild then
            local requested = coordinator.requestRebuild(packId, pendingCoordinatorRebuild)
            if requested then
                moduleRegistry.setPendingCoordinatorRebuild(def, nil)
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
        disposeReceipts(candidateReceipts, "managed_module.activation_rollback_failed",
            tostring(meta.name or moduleId or "module") .. " activation rollback failed")
        if published then
            moduleRegistry.setLiveModule(pluginGuid, previousModule)
            moduleRegistry.setPluginInfo(pluginGuid, previousPluginInfo)
        end
        error(err, 0)
    end

    retireOldModule(previousModule, meta.name or moduleId or "module")
    return true, nil
end

--- Safely activates a constructed managed module by registering external side effects.
--- Returns false plus the activation error instead of throwing.
---@param module ManagedModule
---@return boolean ok
---@return string|nil err
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
