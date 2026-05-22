local deps = ...
local logging = deps.logging
local mutation = deps.mutation
local moduleState = deps.moduleState
local coordinator = deps.coordinator

local function makeCommitContext(actionSnapshot, hadConfigChanges)
    actionSnapshot = actionSnapshot or {}
    local commitActions = moduleState.createCommitActions(actionSnapshot)
    return {
        actions = commitActions,
        hadConfigChanges = function()
            return hadConfigChanges == true
        end,
    }
end

local function notifySettingsCommitted(def, commitNotifier, commitContext)
    if commitNotifier == nil then
        return true, nil
    end

    local ok, result = pcall(commitNotifier, commitContext or makeCommitContext(nil, false))
    if not ok then
        logging.violate("lifecycle.on_settings_committed_failed", "%s: onSettingsCommitted failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(result))
        return true, nil
    end
    if result == false then
        logging.violate("lifecycle.on_settings_committed_false", "%s: onSettingsCommitted returned false",
            tostring(def.name or def.id or "module"))
    end
    return true, nil
end

local function isPackEnabled(packId)
    local coord = packId and coordinator.getConfig(packId)
    if coord and not coord.ModEnabled then
        return false
    end
    return true
end

local function isEnabled(persistentState, packId)
    if not isPackEnabled(packId) then
        return false
    end
    if not persistentState then
        return false
    end
    return persistentState.read("Enabled") == true
end

local function restoreConfigAndRuntime(host, def, stagedState, snapshot, previousEffective, primaryErr)
    stagedState._restoreConfigSnapshot(snapshot)
    stagedState._reloadFromConfig()

    local rollbackOk
    local rollbackErr
    if previousEffective then
        rollbackOk, rollbackErr = mutation.applyForHost(host)
    else
        rollbackOk, rollbackErr = mutation.revertForHost(host)
    end
    if not rollbackOk then
        logging.violate("lifecycle.staged_state_rollback_reapply_failed", "%s: staged state rollback reapply failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(rollbackErr))
        return false, tostring(primaryErr) .. " (rollback reapply failed: " .. tostring(rollbackErr) .. ")"
    end

    return false, primaryErr
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

local function commitStagedState(host, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer)
    local hasPendingActions = actionBuffer and actionBuffer.hasAny()
    if not stagedState.isDirty() and not hasPendingActions then
        return true, nil
    end

    local hadConfigChanges = stagedState._hasConfigChanges()
    local previousEffective = isEnabled(persistentState, def and def.modpack)
    local actionSnapshot = actionBuffer and actionBuffer.captureSnapshot() or {}
    local commitContext = makeCommitContext(actionSnapshot, hadConfigChanges)
    local snapshot = hadConfigChanges and stagedState._captureDirtyConfigSnapshot() or nil
    if hadConfigChanges then
        stagedState._flushToConfig()
    end
    if actionBuffer then
        actionBuffer.clearAll()
    end

    local nextEffective = isEnabled(persistentState, def and def.modpack)
    local shouldSyncMutation = mutation.affectsRunData(mutationBundle)
        and hadConfigChanges

    if not shouldSyncMutation then
        return notifySettingsCommitted(def, commitNotifier, commitContext)
    end

    local ok
    local err
    if nextEffective then
        ok, err = mutation.applyForHost(host)
    elseif previousEffective then
        ok, err = mutation.revertForHost(host)
    else
        ok, err = true, nil
    end
    if ok then
        return notifySettingsCommitted(def, commitNotifier, commitContext)
    end

    return restoreConfigAndRuntime(host, def, stagedState, snapshot, previousEffective, err)
end

local function setEnabled(host, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer, enabled)
    local previousEffective = isEnabled(persistentState, def and def.modpack)
    stagedState.write("Enabled", enabled == true)
    if not stagedState.isDirty() and not (actionBuffer and actionBuffer.hasAny()) then
        if previousEffective and enabled == true and mutation.affectsRunData(mutationBundle) then
            return mutation.applyForHost(host)
        end
        return true, nil
    end
    return commitStagedState(host, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer)
end

local function setDebugMode(host, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer, enabled)
    stagedState.write("DebugMode", enabled == true)
    return commitStagedState(host, def, mutationBundle, commitNotifier, persistentState, stagedState, actionBuffer)
end

return {
    isEnabled = isEnabled,
    resyncStagedState = resyncStagedState,
    commitStagedState = commitStagedState,
    setEnabled = setEnabled,
    setDebugMode = setDebugMode,
}
