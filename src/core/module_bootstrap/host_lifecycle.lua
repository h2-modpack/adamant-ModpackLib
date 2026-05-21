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

local function notifySettingsCommitted(def, settingsObserver, authorHost, store, commitContext)
    if settingsObserver == nil then
        return true, nil
    end

    local ok, result = pcall(settingsObserver, authorHost, store, commitContext or makeCommitContext(nil, false))
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

local function isEnabled(store, packId)
    if not isPackEnabled(packId) then
        return false
    end
    if not store then
        return false
    end
    return store.read("Enabled") == true
end

local function resyncSession(def, session, actions)
    local mismatches = session.auditMismatches()
    if #mismatches > 0 then
        local name = def and (def.name or def.id) or "module"
        logging.violate("lifecycle.session_drift_detected", "%s: session drift detected; reloading staged values for: %s",
            tostring(name),
            table.concat(mismatches, ", "))
        session._reloadFromConfig()
        if actions then
            actions.clearAll()
        end
    end
    return mismatches
end

local function commitSession(host, def, mutationBundle, settingsObserver, authorHost, store, session, actions)
    local hasPendingActions = actions and actions.hasAny()
    if not session.isDirty() and not hasPendingActions then
        return true, nil
    end

    local hadConfigChanges = session._hasConfigChanges()
    local actionSnapshot = actions and actions.captureSnapshot() or {}
    local commitContext = makeCommitContext(actionSnapshot, hadConfigChanges)
    local snapshot = hadConfigChanges and session._captureDirtyConfigSnapshot() or nil
    if hadConfigChanges then
        session._flushToConfig()
    end
    if actions then
        actions.clearAll()
    end

    local shouldReapply = mutation.affectsRunData(mutationBundle)
        and hadConfigChanges
        and isEnabled(store, def and def.modpack)

    if not shouldReapply then
        return notifySettingsCommitted(def, settingsObserver, authorHost, store, commitContext)
    end

    local ok, err = mutation.applyForHost(host)
    if ok then
        return notifySettingsCommitted(def, settingsObserver, authorHost, store, commitContext)
    end

    session._restoreConfigSnapshot(snapshot)
    session._reloadFromConfig()

    local rollbackOk, rollbackErr = mutation.applyForHost(host)
    if not rollbackOk then
        logging.violate("lifecycle.session_rollback_reapply_failed", "%s: session rollback reapply failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(rollbackErr))
        return false, tostring(err) .. " (rollback reapply failed: " .. tostring(rollbackErr) .. ")"
    end

    return false, err
end

local function setEnabled(host, def, store, enabled)
    local nextEnabled = enabled == true
    local currentEnabled = store.read("Enabled") == true
    local packEnabled = isPackEnabled(def and def.modpack)
    local currentEffective = currentEnabled and packEnabled
    local nextEffective = nextEnabled and packEnabled

    local ok, err
    if nextEffective and currentEffective then
        ok, err = mutation.applyForHost(host)
    elseif nextEffective then
        ok, err = mutation.applyForHost(host)
    elseif currentEffective then
        ok, err = mutation.revertForHost(host)
    else
        ok, err = true, nil
    end

    if not ok then
        return false, err
    end

    moduleState.writePersisted(store, "Enabled", nextEnabled)
    return true, nil
end

local function setDebugMode(store, enabled)
    moduleState.writePersisted(store, "DebugMode", enabled == true)
end

return {
    isEnabled = isEnabled,
    resyncSession = resyncSession,
    commitSession = commitSession,
    setEnabled = setEnabled,
    setDebugMode = setDebugMode,
}
