local deps = ...

local logging = deps.logging
local cache = deps.cache
local integrations = deps.integrations
local hooks = deps.hooks
local overlays = deps.overlays
local mutation = deps.mutation
local fallbackUi = deps.fallbackUi
local coordinator = deps.coordinator
local hostRegistry = deps.hostRegistry

local hostActivation = {}

local function CreatePluginInfo(pluginGuid, def)
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
    if warningId == "host.retire_failed" then
        logging.violate("host.retire_failed", "%s: %s", warningPrefix, table.concat(errors, "; "))
    elseif warningId == "host.activation_rollback_failed" then
        logging.violate("host.activation_rollback_failed", "%s: %s", warningPrefix, table.concat(errors, "; "))
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

local function retireOldHost(previousHost, replacementLabel)
    local oldRecord = hostRegistry.getRecord(previousHost)
    local receipts = oldRecord and oldRecord.effectReceipts or nil
    if type(receipts) ~= "table" or #receipts == 0 then
        return
    end
    disposeReceipts(receipts, "host.retire_failed", tostring(replacementLabel) .. " old host retirement failed")
    oldRecord.effectReceipts = {}
end

--- Activates a constructed module host by registering external side effects.
---@param host ModuleHost
---@return AuthorHost host Module author host view.
function hostActivation.activateOrThrow(host)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("host.invalid_activate_opts", "moduleHost.activateOrThrow: host is required")
    end

    local pluginGuid = host.getHostId()
    local store = record.store
    local authorHost = record.authorHost
    local def = record.definition

    if record.activated == true then
        logging.violate("host.already_activated", "moduleHost.activateOrThrow: host is already activated")
    end
    if record.activating == true then
        logging.violate("host.activation_in_progress", "moduleHost.activateOrThrow: host activation is already in progress")
    end
    local meta = host.getMeta()
    local moduleId = host.getModuleId()
    local packId = host.getPackId()
    local pendingCoordinatorRebuild = hostRegistry.getPendingCoordinatorRebuild(def)
    local hasPendingCoordinatorRebuild = pendingCoordinatorRebuild ~= nil
    local previousHost = hostRegistry.getLiveHost(pluginGuid)
    local previousPluginInfo = hostRegistry.getPluginInfo(pluginGuid)
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
        addReceipt("sharedCache", cache.shared.install(pluginGuid, record.sharedCachePublications), true)
        addReceipt("integrations", integrations.installForHost(host), true)
        addReceipt("hooks", hooks.installForHost(host), true)
        addReceipt("overlays", overlays.installForHost(host, authorHost, store), true)

        if not hasPendingCoordinatorRebuild then
            addReceipt("mutation", mutation.syncForHost(host), false)
        elseif hasPendingCoordinatorRebuild then
            local requested = coordinator.requestRebuild(packId, pendingCoordinatorRebuild)
            if requested then
                hostRegistry.setPendingCoordinatorRebuild(def, nil)
            else
                logging.violate(
                    "host.structural_rebuild_unavailable",
                    "%s structural definition changed during hot reload; full reload required",
                    tostring(meta.name or moduleId or "module"))
            end
        end
        if record.fallbackUiRequested == true then
            addReceipt("fallbackUi", fallbackUi.installForHost(host), true)
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
        hostRegistry.setLiveHost(pluginGuid, host)
        hostRegistry.setPluginInfo(pluginGuid, CreatePluginInfo(pluginGuid, def))
        published = true
    end)

    if not ok then
        record.activating = false
        record.activated = false
        disposeReceipts(candidateReceipts, "host.activation_rollback_failed",
            tostring(meta.name or moduleId or "module") .. " activation rollback failed")
        if published then
            hostRegistry.setLiveHost(pluginGuid, previousHost)
            hostRegistry.setPluginInfo(pluginGuid, previousPluginInfo)
        end
        error(err, 0)
    end

    retireOldHost(previousHost, meta.name or moduleId or "module")
    return authorHost
end

--- Safely activates a constructed module host by registering external side effects.
--- Returns false plus the activation error instead of throwing.
---@param host ModuleHost
---@return boolean ok
---@return string|nil err
function hostActivation.activate(host)
    local ok, err = pcall(hostActivation.activateOrThrow, host)
    if ok then
        return true, nil
    end

    err = tostring(err)
    logging.violate("host.activate_failed", "host.activate failed; skipping module: %s", err)
    return false, err
end

return hostActivation
