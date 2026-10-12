local deps = ...
local logging = deps.logging
local moduleState = deps.moduleState

local PACK_RESTORE_MARKER_ALIAS = "__Modpack_PackRestoreMarker"
local PACK_RESTORE_NONE = 0
local PACK_RESTORE_DISABLED = 1
local PACK_RESTORE_ENABLED = 2

local ReloadReasons = {
    manual = true,
    frameworkSnapshot = true,
    hashReload = true,
    driftRepair = true,
}

local lifecycle = {}

local function labelOf(def)
    return tostring(def.name or def.id or "module")
end

local function makeCommitContext(actionSnapshot, hadConfigChanges)
    return {
        actions = moduleState.createCommitActions(actionSnapshot),
        _actionSnapshot = actionSnapshot,
        hadConfigChanges = function()
            return hadConfigChanges == true
        end,
    }
end

-- One post-flush commit step. Failures and `false` results are reported, never propagated:
-- the config flush already succeeded, so the commit itself still succeeds.
local function runCommitStep(def, label, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        logging.violate("lifecycle.on_commit_failed", "%s: %s failed: %s", labelOf(def), label, tostring(result))
    elseif result == false then
        logging.violate("lifecycle.on_commit_false", "%s: %s returned false", labelOf(def), label)
    end
end

local function makeReloadContext(reason, receipt)
    receipt = receipt or {}
    return {
        reason = function()
            return reason
        end,
        hadCommittedChanges = function()
            return receipt.hadCommittedChanges == true
        end,
        hadSettingChanges = function()
            return receipt.hadSettingChanges == true
        end,
        hadStatusChanges = function()
            return receipt.hadStatusChanges == true
        end,
    }
end

local function normalizeReloadReason(reason)
    reason = reason or "manual"
    if ReloadReasons[reason] ~= true then
        logging.violate(
            "lifecycle.invalid_reload_reason",
            "module.reloadFromConfig: unknown reason '%s'",
            tostring(reason)
        )
    end
    return reason
end

---Composes the commit notifier: the author `onCommit` observer, then overlay commit dispatch.
---Both always run; the notifier raises if either failed and otherwise returns the observer result.
---@param opts AdamantModpackLib.CommitNotifierOpts
---@return fun(commit: table): any
function lifecycle.createCommitNotifier(opts)
    local onCommit = opts.onCommit
    local dispatchOverlayCommit = opts.dispatchOverlayCommit
    return function(commit)
        local observerOk = true
        local observerResult = nil
        if onCommit ~= nil then
            observerOk, observerResult = pcall(onCommit, opts.host, opts.runtime, commit)
        end

        local overlayOk, overlayErr = pcall(dispatchOverlayCommit, commit)
        if not observerOk then
            if not overlayOk then
                error(tostring(observerResult) .. " (overlay dispatch failed: " .. tostring(overlayErr) .. ")", 0)
            end
            error(observerResult, 0)
        end
        if not overlayOk then
            error(overlayErr, 0)
        end
        return observerResult
    end
end

---Composes the reload notifier around the optional author `onReload` observer.
---@param opts AdamantModpackLib.ReloadNotifierOpts
---@return fun(reason: string, receipt: table?): AdamantModpackLib.ReloadContext
function lifecycle.createReloadNotifier(opts)
    local onReload = opts.onReload
    return function(reason, receipt)
        local context = makeReloadContext(reason, receipt)
        if onReload == nil then
            return context
        end
        local ok, result = pcall(onReload, opts.host, opts.runtime, context)
        if not ok then
            logging.violate("lifecycle.on_reload_failed", "%s: onReload failed: %s", labelOf(opts.def), tostring(result))
        elseif result == false then
            logging.violate("lifecycle.on_reload_false", "%s: onReload returned false", labelOf(opts.def))
        end
        return context
    end
end

---Binds commit/reload/enable/pack-transition operations to one module session.
---Every returned op is exposed as an activation-gated managed-module method of the same name.
---@param session AdamantModpackLib.LifecycleSession
function lifecycle.bind(session)
    local def = session.def
    local txn = session.txn
    local mutation = session.mutation
    local ops = {}

    local function isEnabled()
        return txn.readCommitted("Enabled") == true
    end

    local function finishSuccessfulCommit(commit)
        local actionSnapshot = commit.actionSnapshot
        if next(actionSnapshot) ~= nil then
            runCommitStep(def, "action handler", session.runActions, actionSnapshot)
        end
        runCommitStep(def, "status reset", txn.applyStatusReset, commit)
        runCommitStep(def, "shared event flush", session.flushSharedEvents)
        txn.finish()
        runCommitStep(def, "onCommit", session.notifyCommit, makeCommitContext(actionSnapshot, commit.hadConfigChanges))
        return true, nil
    end

    local function restoreConfigAndRuntime(commit, previousEffective, primaryErr)
        txn.rollback(commit)

        local rollbackOk
        local rollbackErr
        if previousEffective then
            rollbackOk, rollbackErr = mutation.apply()
        else
            rollbackOk, rollbackErr = mutation.revert()
        end
        if not rollbackOk then
            logging.violate("lifecycle.staged_state_rollback_reapply_failed",
                "%s: staged state rollback reapply failed: %s", labelOf(def), tostring(rollbackErr))
            return false, tostring(primaryErr) .. " (rollback reapply failed: " .. tostring(rollbackErr) .. ")"
        end

        return false, primaryErr
    end

    local function commit()
        if not txn.hasPending() then
            return true, nil
        end

        local previousEffective = isEnabled()
        local pending = txn.beginCommit()
        local nextEffective = isEnabled()
        if not (mutation.affectsRunData() and pending.hadConfigChanges) then
            return finishSuccessfulCommit(pending)
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
            return finishSuccessfulCommit(pending)
        end

        return restoreConfigAndRuntime(pending, previousEffective, err)
    end

    local function stageLifecycleBoolean(alias, enabled)
        local target = enabled == true
        local previous = txn.readCommitted(alias) == true
        txn.stage(alias, target)
        if not txn.isDirty() and previous ~= target then
            txn.syncFromCommitted()
            txn.stage(alias, target)
        end
        return previous
    end

    local function makePackTransitionReceipt()
        return {
            previousEnabled = txn.readCommitted("Enabled") == true,
            previousMarker = txn.readCommitted(PACK_RESTORE_MARKER_ALIAS),
        }
    end

    local function stagePackTransitionReceipt(receipt)
        txn.stage(PACK_RESTORE_MARKER_ALIAS, receipt and receipt.previousMarker or PACK_RESTORE_NONE)
        txn.stage("Enabled", receipt and receipt.previousEnabled == true)
    end

    ops.flush = commit

    function ops.writeAndFlush(alias, value)
        txn.stage(alias, value)
        return commit()
    end

    function ops.commitIfDirty()
        if not txn.hasPending() then
            return true, nil, false
        end
        local ok, err = commit()
        return ok, err, ok == true
    end

    function ops.resetAll(resetOpts)
        return txn.queueResetAll(resetOpts)
    end

    function ops.reloadFromConfig(reason)
        reason = normalizeReloadReason(reason)
        return session.notifyReload(reason, txn.reload())
    end

    function ops.resync()
        local mismatches = txn.auditMismatches()
        if #mismatches == 0 then
            return mismatches, nil
        end
        logging.violate("lifecycle.staged_state_drift_detected",
            "%s: staged state drift detected; reloading staged values for: %s",
            labelOf(def), table.concat(mismatches, ", "))
        return mismatches, session.notifyReload("driftRepair", txn.reload())
    end

    function ops.setEnabled(enabled)
        local previousEffective = stageLifecycleBoolean("Enabled", enabled)
        if not txn.hasPending() then
            if previousEffective and enabled == true and mutation.affectsRunData() then
                return mutation.apply()
            end
            return true, nil
        end
        return commit()
    end

    function ops.setDebugMode(enabled)
        stageLifecycleBoolean("DebugMode", enabled)
        return commit()
    end

    function ops.suspendForPackDisable()
        local receipt = makePackTransitionReceipt()
        txn.stage(PACK_RESTORE_MARKER_ALIAS, receipt.previousEnabled and PACK_RESTORE_ENABLED or PACK_RESTORE_DISABLED)
        local ok, err = ops.setEnabled(false)
        return ok, err, receipt
    end

    function ops.ensureSuspendedForPackDisable()
        local marker = txn.readCommitted(PACK_RESTORE_MARKER_ALIAS)
        if marker == PACK_RESTORE_NONE or marker == nil then
            return ops.suspendForPackDisable()
        end
        if txn.readCommitted("Enabled") ~= true then
            return true, nil, nil
        end

        txn.stage("Enabled", false)
        return commit()
    end

    function ops.restoreForPackEnable()
        local receipt = makePackTransitionReceipt()
        local marker = txn.readCommitted(PACK_RESTORE_MARKER_ALIAS)
        local target = receipt.previousEnabled
        if marker == PACK_RESTORE_ENABLED then
            target = true
        elseif marker == PACK_RESTORE_DISABLED then
            target = false
        end

        txn.stage(PACK_RESTORE_MARKER_ALIAS, PACK_RESTORE_NONE)
        local ok, err = ops.setEnabled(target)
        return ok, err, receipt
    end

    function ops.rollbackPackTransition(receipt)
        stagePackTransitionReceipt(receipt)
        return commit()
    end

    function ops.restorePackTransitionState(receipt)
        stagePackTransitionReceipt(receipt)
        txn.flushWithoutCommit()
        return true, nil
    end

    return ops
end

return lifecycle
