local deps = ...

local CloneValue = deps.values.deepCopy

---Commit/reload transaction over one module's staged state, action buffer, and
---queued status reset. Handed only to the managed-module lifecycle.
---@param persistentState AdamantModpackLib.PersistentState
---@param stagedView AdamantModpackLib.StagedState
---@param staged AdamantModpackLib.StagedTxnInternals
---@param status AdamantModpackLib.StatusState
---@param actionBuffer table
---@return AdamantModpackLib.ModuleStateTxn
local function create(persistentState, stagedView, staged, status, actionBuffer)
    -- Pending status reset opts, or nil. Applied during a successful commit only.
    local queuedStatusReset = nil
    local txn = {
        readCommitted = persistentState.read,
        stage = stagedView.write,
        isDirty = staged.isDirty,
        syncFromCommitted = staged.syncFromCommitted,
        auditMismatches = staged.auditMismatches,
    }

    local function discardIntent()
        actionBuffer.clearAll()
        queuedStatusReset = nil
    end

    function txn.hasPending()
        return staged.isDirty() or actionBuffer.hasAny() or queuedStatusReset ~= nil
    end

    ---Stage a full module reset: staged data resets now, pending action intent is
    ---dropped, and status reset is queued for the next commit.
    function txn.queueResetAll(opts)
        local stagedChanged, stagedCount = staged.resetAll(opts)
        actionBuffer.clearAll()
        local statusChanged, statusCount = status.countResettable(opts)
        if statusChanged then
            queuedStatusReset = { opts = CloneValue(opts) }
        else
            queuedStatusReset = nil
        end
        return stagedChanged or statusChanged, stagedCount + statusCount
    end

    ---Flush dirty staged data and take pending intent for this commit.
    ---The returned commit record is the rollback token.
    function txn.beginCommit()
        local commit = {
            actionSnapshot = actionBuffer.captureSnapshot(),
            hadConfigChanges = false,
            configSnapshot = nil,
            statusReset = queuedStatusReset,
        }
        queuedStatusReset = nil
        if staged.isDirty() then
            commit.configSnapshot = staged.captureDirtyConfigSnapshot()
            staged.flushToConfig()
            commit.hadConfigChanges = true
        end
        return commit
    end

    function txn.applyStatusReset(commit)
        if commit.statusReset ~= nil then
            status.resetAll(commit.statusReset.opts)
        end
    end

    function txn.finish()
        discardIntent()
    end

    function txn.rollback(commit)
        discardIntent()
        staged.restoreConfigSnapshot(commit.configSnapshot)
        staged.reloadFromConfig()
    end

    ---Flush staged data without running commit effects; pending intent is dropped.
    function txn.flushWithoutCommit()
        staged.flushToConfig()
        discardIntent()
    end

    function txn.reload()
        local receipt = staged.reloadFromConfig()
        discardIntent()
        return receipt
    end

    return txn
end

return {
    create = create,
}
