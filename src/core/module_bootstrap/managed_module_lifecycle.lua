local deps = ...
local logging = deps.logging
local mutation = deps.mutation
local moduleState = deps.moduleState

local PACK_RESTORE_SNAPSHOT_ALIAS = "AdamantFramework_PackRestoreSnapshot"
local PACK_RESTORE_NONE = 0
local PACK_RESTORE_DISABLED = 1
local PACK_RESTORE_ENABLED = 2

local function debugValue(value)
    return tostring(value)
end

local function readPersistentAlias(persistentState, alias)
    if persistentState and type(persistentState.read) == "function" then
        return persistentState.read(alias)
    end
    return nil
end

local function readStagedAlias(stagedState, alias)
    if stagedState and type(stagedState.read) == "function" then
        return stagedState.read(alias)
    end
    return nil
end

local function isStagedDirty(stagedState)
    if stagedState and type(stagedState.isDirty) == "function" then
        return stagedState.isDirty()
    end
    return nil
end

local function debugLifecycle(def, fmt, ...)
    if rawget(_G, "AdamantEnableToggleDebug") ~= true then
        return
    end
    logging.printWithPrefix("[lib-debug] ", "%s: " .. fmt, tostring(def and (def.name or def.id) or "module"), ...)
end

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

local function executeInternalActionsDuringCommit(def, internalActionExecutor, internalActionSnapshot)
    if internalActionExecutor == nil or internalActionSnapshot == nil or next(internalActionSnapshot) == nil then
        return
    end

    local ok, result = pcall(internalActionExecutor, internalActionSnapshot)
    if not ok then
        logging.violate("lifecycle.on_commit_failed", "%s: internal action handler failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(result))
        return
    end
    if result == false then
        logging.violate("lifecycle.on_commit_false", "%s: internal action handler returned false",
            tostring(def.name or def.id or "module"))
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

local function isEnabled(persistentState)
    if not persistentState then
        return false
    end
    return persistentState.read("Enabled") == true
end

local function restoreConfigAndRuntime(module, def, stagedState, snapshot, previousEffective, primaryErr)
    stagedState._restoreConfigSnapshot(snapshot)
    stagedState._reloadFromConfig()

    local rollbackOk
    local rollbackErr
    if previousEffective then
        rollbackOk, rollbackErr = mutation.applyForModule(module)
    else
        rollbackOk, rollbackErr = mutation.revertForModule(module)
    end
    if not rollbackOk then
        logging.violate("lifecycle.staged_state_rollback_reapply_failed", "%s: staged state rollback reapply failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(rollbackErr))
        return false, tostring(primaryErr) .. " (rollback reapply failed: " .. tostring(rollbackErr) .. ")"
    end

    return false, primaryErr
end

local function flushDirtyConfig(stagedState)
    if not stagedState._hasConfigChanges() then
        return false, nil
    end
    local snapshot = stagedState._captureDirtyConfigSnapshot()
    stagedState._flushToConfig()
    return true, snapshot
end

local function resyncStagedState(def, stagedState, actionBuffer)
    local mismatches = stagedState.auditMismatches()
    if #mismatches > 0 then
        local name = def and (def.name or def.id) or "module"
        logging.violate("lifecycle.staged_state_drift_detected", "%s: staged state drift detected; reloading staged values for: %s",
            tostring(name),
            table.concat(mismatches, ", "))
        stagedState._reloadFromConfig()
        if actionBuffer then
            actionBuffer.clearAll()
        end
    end
    return mismatches
end

local function stageLifecycleBoolean(persistentState, stagedState, alias, enabled)
    local target = enabled == true
    local previous = persistentState.read(alias) == true
    stagedState.write(alias, target)
    if not stagedState.isDirty() and previous ~= target then
        stagedState._syncFromCommitted()
        stagedState.write(alias, target)
    end
    return previous, target
end

local function finishSuccessfulCommit(def, commitNotifier, commitContext, actionBuffer, actionExecutor, actionSnapshot,
                                      internalActionExecutor, internalActionSnapshot, sharedEventFlusher)
    executeActionsDuringCommit(def, actionExecutor, actionSnapshot)
    executeInternalActionsDuringCommit(def, internalActionExecutor, internalActionSnapshot)
    flushSharedEventsDuringCommit(def, sharedEventFlusher)
    if actionBuffer then
        actionBuffer.clearAll()
    end
    return notifyCommitAfterFlush(def, commitNotifier, commitContext)
end

local function commitStagedState(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
                                 actionExecutor, sharedEventFlusher, internalActionExecutor)
    local hasPendingActions = actionBuffer and actionBuffer.hasAny()
    debugLifecycle(def,
        "commitStagedState enter enabled_committed=%s enabled_staged=%s dirty=%s actions=%s",
        debugValue(readPersistentAlias(persistentState, "Enabled")),
        debugValue(readStagedAlias(stagedState, "Enabled")),
        debugValue(isStagedDirty(stagedState)),
        debugValue(hasPendingActions == true))
    if not stagedState.isDirty() and not hasPendingActions then
        debugLifecycle(def, "commitStagedState no-op")
        return true, nil
    end

    local actionSnapshot = actionBuffer and actionBuffer.captureSnapshot() or {}
    local internalActionSnapshot = actionBuffer and actionBuffer.captureInternalSnapshot() or {}
    local previousEffective = isEnabled(persistentState)
    local hadConfigChanges, snapshot = flushDirtyConfig(stagedState)

    local nextEffective = isEnabled(persistentState)
    debugLifecycle(def,
        "commitStagedState flushed changed=%s previous_enabled=%s next_enabled=%s enabled_committed=%s enabled_staged=%s dirty=%s",
        debugValue(hadConfigChanges),
        debugValue(previousEffective),
        debugValue(nextEffective),
        debugValue(readPersistentAlias(persistentState, "Enabled")),
        debugValue(readStagedAlias(stagedState, "Enabled")),
        debugValue(isStagedDirty(stagedState)))
    local commitContext = makeCommitContext(actionSnapshot, hadConfigChanges)
    local shouldSyncMutation = mutation.affectsRunData(mutationBundle)
        and hadConfigChanges

    if not shouldSyncMutation then
        return finishSuccessfulCommit(def, commitNotifier, commitContext, actionBuffer, actionExecutor, actionSnapshot,
            internalActionExecutor, internalActionSnapshot, sharedEventFlusher)
    end

    local ok
    local err
    if nextEffective then
        ok, err = mutation.applyForModule(module)
    elseif previousEffective then
        ok, err = mutation.revertForModule(module)
    else
        ok, err = true, nil
    end
    if ok then
        return finishSuccessfulCommit(def, commitNotifier, commitContext, actionBuffer, actionExecutor, actionSnapshot,
            internalActionExecutor, internalActionSnapshot, sharedEventFlusher)
    end

    if actionBuffer then
        actionBuffer.clearAll()
    end
    return restoreConfigAndRuntime(module, def, stagedState, snapshot, previousEffective, err)
end

local function setEnabled(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
                          actionExecutor, sharedEventFlusher, internalActionExecutor, enabled)
    debugLifecycle(def,
        "setEnabled begin target=%s committed=%s staged=%s dirty=%s",
        debugValue(enabled == true),
        debugValue(readPersistentAlias(persistentState, "Enabled")),
        debugValue(readStagedAlias(stagedState, "Enabled")),
        debugValue(isStagedDirty(stagedState)))
    local previousEffective = stageLifecycleBoolean(persistentState, stagedState, "Enabled", enabled)
    debugLifecycle(def,
        "setEnabled staged target=%s previous=%s committed=%s staged=%s dirty=%s",
        debugValue(enabled == true),
        debugValue(previousEffective),
        debugValue(readPersistentAlias(persistentState, "Enabled")),
        debugValue(readStagedAlias(stagedState, "Enabled")),
        debugValue(isStagedDirty(stagedState)))
    if not stagedState.isDirty() and not (actionBuffer and actionBuffer.hasAny()) then
        if previousEffective and enabled == true and mutation.affectsRunData(mutationBundle) then
            local ok, err = mutation.applyForModule(module)
            debugLifecycle(def, "setEnabled reapply active mutation ok=%s err=%s committed=%s staged=%s",
                debugValue(ok), debugValue(err), debugValue(readPersistentAlias(persistentState, "Enabled")),
                debugValue(readStagedAlias(stagedState, "Enabled")))
            return ok, err
        end
        debugLifecycle(def, "setEnabled no-op target=%s committed=%s staged=%s",
            debugValue(enabled == true), debugValue(readPersistentAlias(persistentState, "Enabled")),
            debugValue(readStagedAlias(stagedState, "Enabled")))
        return true, nil
    end
    local ok, err = commitStagedState(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
        actionExecutor, sharedEventFlusher, internalActionExecutor)
    debugLifecycle(def, "setEnabled end ok=%s err=%s committed=%s staged=%s dirty=%s",
        debugValue(ok), debugValue(err), debugValue(readPersistentAlias(persistentState, "Enabled")),
        debugValue(readStagedAlias(stagedState, "Enabled")), debugValue(isStagedDirty(stagedState)))
    return ok, err
end

local function setDebugMode(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
                            actionExecutor, sharedEventFlusher, internalActionExecutor, enabled)
    stageLifecycleBoolean(persistentState, stagedState, "DebugMode", enabled)
    return commitStagedState(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
        actionExecutor, sharedEventFlusher, internalActionExecutor)
end

local function makePackTransitionReceipt(persistentState)
    return {
        previousEnabled = persistentState.read("Enabled") == true,
        previousMarker = persistentState.read(PACK_RESTORE_SNAPSHOT_ALIAS),
    }
end

local function stagePackTransitionReceipt(stagedState, receipt)
    stagedState.write(PACK_RESTORE_SNAPSHOT_ALIAS, receipt and receipt.previousMarker or PACK_RESTORE_NONE)
    stagedState.write("Enabled", receipt and receipt.previousEnabled == true)
end

local function suspendForPackDisable(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
                                     actionExecutor, sharedEventFlusher, internalActionExecutor)
    local receipt = makePackTransitionReceipt(persistentState)
    local marker = receipt.previousEnabled and PACK_RESTORE_ENABLED or PACK_RESTORE_DISABLED
    stagedState.write(PACK_RESTORE_SNAPSHOT_ALIAS, marker)
    local ok, err = setEnabled(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
        actionExecutor, sharedEventFlusher, internalActionExecutor, false)
    return ok, err, receipt
end

local function ensureSuspendedForPackDisable(module, def, mutationBundle, commitNotifier, persistentState, stagedState,
                                             actionBuffer, actionExecutor, sharedEventFlusher, internalActionExecutor)
    local marker = persistentState.read(PACK_RESTORE_SNAPSHOT_ALIAS)
    if marker == PACK_RESTORE_NONE or marker == nil then
        return suspendForPackDisable(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
            actionExecutor, sharedEventFlusher, internalActionExecutor)
    end
    if persistentState.read("Enabled") ~= true then
        return true, nil, nil
    end

    stagedState.write("Enabled", false)
    return commitStagedState(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
        actionExecutor, sharedEventFlusher, internalActionExecutor)
end

local function restoreForPackEnable(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
                                    actionExecutor, sharedEventFlusher, internalActionExecutor)
    local receipt = makePackTransitionReceipt(persistentState)
    local marker = persistentState.read(PACK_RESTORE_SNAPSHOT_ALIAS)
    local target = receipt.previousEnabled
    if marker == PACK_RESTORE_ENABLED then
        target = true
    elseif marker == PACK_RESTORE_DISABLED then
        target = false
    end

    stagedState.write(PACK_RESTORE_SNAPSHOT_ALIAS, PACK_RESTORE_NONE)
    local ok, err = setEnabled(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
        actionExecutor, sharedEventFlusher, internalActionExecutor, target)
    return ok, err, receipt
end

local function rollbackPackTransition(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
                                      actionExecutor, sharedEventFlusher, internalActionExecutor, receipt)
    stagePackTransitionReceipt(stagedState, receipt)
    return commitStagedState(module, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer,
        actionExecutor, sharedEventFlusher, internalActionExecutor)
end

local function restorePackTransitionState(stagedState, actionBuffer, receipt)
    stagePackTransitionReceipt(stagedState, receipt)
    stagedState._flushToConfig()
    if actionBuffer then
        actionBuffer.clearAll()
    end
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
