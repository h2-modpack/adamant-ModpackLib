local deps = ...
local logging = deps.logging
local moduleState = deps.moduleState

local PACK_RESTORE_MARKER_ALIAS = "__Modpack_PackRestoreMarker"
local PACK_RESTORE_NONE = 0
local PACK_RESTORE_DISABLED = 1
local PACK_RESTORE_ENABLED = 2

local function makeCommitContext(actionSnapshot, hadConfigChanges)
    actionSnapshot = actionSnapshot or {}
    local commitActions = moduleState.createCommitActions(actionSnapshot)
    return {
        actions = commitActions,
        _actionSnapshot = actionSnapshot,
        hadConfigChanges = function()
            return hadConfigChanges == true
        end,
    }
end

local function notifyCommit(def, commitNotifier, commitContext)
    if commitNotifier == nil then
        return true, nil
    end

    local ok, result = pcall(commitNotifier, commitContext or makeCommitContext(nil, false))
    if not ok then
        logging.violate("lifecycle.on_commit_failed", "%s: onCommit failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(result))
        return true, nil
    end
    if result == false then
        logging.violate("lifecycle.on_commit_false", "%s: onCommit returned false",
            tostring(def.name or def.id or "module"))
    end
    return true, nil
end

local function notifyCommitAfterFlush(def, commitNotifier, commitContext)
    local ok, err = notifyCommit(def, commitNotifier, commitContext)
    return ok, err
end

local function executeActionsDuringCommit(def, actionExecutor, actionSnapshot)
    if actionExecutor == nil or actionSnapshot == nil or next(actionSnapshot) == nil then
        return
    end

    local ok, result = pcall(actionExecutor, actionSnapshot)
    if not ok then
        logging.violate("lifecycle.on_commit_failed", "%s: action handler failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(result))
        return
    end
    if result == false then
        logging.violate("lifecycle.on_commit_false", "%s: action handler returned false",
            tostring(def.name or def.id or "module"))
    end
end

local function applyStatusResetDuringCommit(def, txn, commit)
    if commit.statusReset == nil then
        return
    end

    local ok, result = pcall(txn.applyStatusReset, commit)
    if not ok then
        logging.violate("lifecycle.on_commit_failed", "%s: status reset failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(result))
    end
end

local function flushSharedEventsDuringCommit(def, sharedEventFlusher)
    if sharedEventFlusher == nil then
        return
    end

    local ok, result = pcall(sharedEventFlusher)
    if not ok then
        logging.violate("lifecycle.on_commit_failed", "%s: shared event flush failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(result))
        return
    end
    if result == false then
        logging.violate("lifecycle.on_commit_false", "%s: shared event flush returned false",
            tostring(def.name or def.id or "module"))
    end
end

---@param txn AdamantModpackLib.ModuleStateTxn
local function isEnabled(txn)
    return txn.readCommitted("Enabled") == true
end

local function restoreConfigAndRuntime(def, mutation, txn, commit, previousEffective, primaryErr)
    txn.rollback(commit)

    local rollbackOk
    local rollbackErr
    if previousEffective then
        rollbackOk, rollbackErr = mutation.apply()
    else
        rollbackOk, rollbackErr = mutation.revert()
    end
    if not rollbackOk then
        logging.violate("lifecycle.staged_state_rollback_reapply_failed", "%s: staged state rollback reapply failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(rollbackErr))
        return false, tostring(primaryErr) .. " (rollback reapply failed: " .. tostring(rollbackErr) .. ")"
    end

    return false, primaryErr
end

local function resyncStagedState(def, txn)
    local mismatches = txn.auditMismatches()
    local reloadReceipt = nil
    if #mismatches > 0 then
        local name = def and (def.name or def.id) or "module"
        logging.violate("lifecycle.staged_state_drift_detected", "%s: staged state drift detected; reloading staged values for: %s",
            tostring(name),
            table.concat(mismatches, ", "))
        reloadReceipt = txn.reload()
    end
    return mismatches, reloadReceipt
end

local function stageLifecycleBoolean(txn, alias, enabled)
    local target = enabled == true
    local previous = txn.readCommitted(alias) == true
    txn.stage(alias, target)
    if not txn.isDirty() and previous ~= target then
        txn.syncFromCommitted()
        txn.stage(alias, target)
    end
    return previous, target
end

local function finishSuccessfulCommit(def, commitNotifier, txn, commit, actionExecutor, sharedEventFlusher)
    executeActionsDuringCommit(def, actionExecutor, commit.actionSnapshot)
    applyStatusResetDuringCommit(def, txn, commit)
    flushSharedEventsDuringCommit(def, sharedEventFlusher)
    txn.finish()
    return notifyCommitAfterFlush(def, commitNotifier, makeCommitContext(commit.actionSnapshot, commit.hadConfigChanges))
end

---@param def table Prepared definition.
---@param mutation AdamantModpackLib.BoundMutation
---@param txn AdamantModpackLib.ModuleStateTxn
local function commitStagedState(def, mutation, commitNotifier, txn, actionExecutor, sharedEventFlusher)
    if not txn.hasPending() then
        return true, nil
    end

    local previousEffective = isEnabled(txn)
    local commit = txn.beginCommit()
    local nextEffective = isEnabled(txn)
    local shouldSyncMutation = mutation.affectsRunData()
        and commit.hadConfigChanges

    if not shouldSyncMutation then
        return finishSuccessfulCommit(def, commitNotifier, txn, commit, actionExecutor, sharedEventFlusher)
    end

    local ok
    local err
    if nextEffective then
        ok, err = mutation.apply()
    elseif previousEffective then
        ok, err = mutation.revert()
    else
        ok, err = true, nil
    end
    if ok then
        return finishSuccessfulCommit(def, commitNotifier, txn, commit, actionExecutor, sharedEventFlusher)
    end

    return restoreConfigAndRuntime(def, mutation, txn, commit, previousEffective, err)
end

local function setEnabled(def, mutation, commitNotifier, txn, actionExecutor, sharedEventFlusher, enabled)
    local previousEffective = stageLifecycleBoolean(txn, "Enabled", enabled)
    if not txn.hasPending() then
        if previousEffective and enabled == true and mutation.affectsRunData() then
            local ok, err = mutation.apply()
            return ok, err
        end
        return true, nil
    end
    return commitStagedState(def, mutation, commitNotifier, txn, actionExecutor, sharedEventFlusher)
end

local function setDebugMode(def, mutation, commitNotifier, txn, actionExecutor, sharedEventFlusher, enabled)
    stageLifecycleBoolean(txn, "DebugMode", enabled)
    return commitStagedState(def, mutation, commitNotifier, txn, actionExecutor, sharedEventFlusher)
end

local function makePackTransitionReceipt(txn)
    return {
        previousEnabled = txn.readCommitted("Enabled") == true,
        previousMarker = txn.readCommitted(PACK_RESTORE_MARKER_ALIAS),
    }
end

local function stagePackTransitionReceipt(txn, receipt)
    txn.stage(PACK_RESTORE_MARKER_ALIAS, receipt and receipt.previousMarker or PACK_RESTORE_NONE)
    txn.stage("Enabled", receipt and receipt.previousEnabled == true)
end

local function suspendForPackDisable(def, mutation, commitNotifier, txn, actionExecutor, sharedEventFlusher)
    local receipt = makePackTransitionReceipt(txn)
    local marker = receipt.previousEnabled and PACK_RESTORE_ENABLED or PACK_RESTORE_DISABLED
    txn.stage(PACK_RESTORE_MARKER_ALIAS, marker)
    local ok, err = setEnabled(def, mutation, commitNotifier, txn, actionExecutor, sharedEventFlusher,
        false)
    return ok, err, receipt
end

local function ensureSuspendedForPackDisable(def, mutation, commitNotifier, txn, actionExecutor,
                                             sharedEventFlusher)
    local marker = txn.readCommitted(PACK_RESTORE_MARKER_ALIAS)
    if marker == PACK_RESTORE_NONE or marker == nil then
        return suspendForPackDisable(def, mutation, commitNotifier, txn, actionExecutor,
            sharedEventFlusher)
    end
    if txn.readCommitted("Enabled") ~= true then
        return true, nil, nil
    end

    txn.stage("Enabled", false)
    return commitStagedState(def, mutation, commitNotifier, txn, actionExecutor, sharedEventFlusher)
end

local function restoreForPackEnable(def, mutation, commitNotifier, txn, actionExecutor, sharedEventFlusher)
    local receipt = makePackTransitionReceipt(txn)
    local marker = txn.readCommitted(PACK_RESTORE_MARKER_ALIAS)
    local target = receipt.previousEnabled
    if marker == PACK_RESTORE_ENABLED then
        target = true
    elseif marker == PACK_RESTORE_DISABLED then
        target = false
    end

    txn.stage(PACK_RESTORE_MARKER_ALIAS, PACK_RESTORE_NONE)
    local ok, err = setEnabled(def, mutation, commitNotifier, txn, actionExecutor, sharedEventFlusher,
        target)
    return ok, err, receipt
end

local function rollbackPackTransition(def, mutation, commitNotifier, txn, actionExecutor,
                                      sharedEventFlusher, receipt)
    stagePackTransitionReceipt(txn, receipt)
    return commitStagedState(def, mutation, commitNotifier, txn, actionExecutor, sharedEventFlusher)
end

local function restorePackTransitionState(txn, receipt)
    stagePackTransitionReceipt(txn, receipt)
    txn.flushWithoutCommit()
    return true, nil
end

return {
    isEnabled = isEnabled,
    resyncStagedState = resyncStagedState,
    commitStagedState = commitStagedState,
    setEnabled = setEnabled,
    setDebugMode = setDebugMode,
    suspendForPackDisable = suspendForPackDisable,
    ensureSuspendedForPackDisable = ensureSuspendedForPackDisable,
    restoreForPackEnable = restoreForPackEnable,
    rollbackPackTransition = rollbackPackTransition,
    restorePackTransitionState = restorePackTransitionState,
}
