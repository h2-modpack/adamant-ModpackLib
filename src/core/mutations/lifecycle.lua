local deps = ...

local logging = deps.logging
local coordinator = deps.coordinator
local setupRunData = deps.setupRunData
local mutationState = deps.mutationState
local plan = deps.plan

local lifecycle = {
    createBackup = plan.createBackup,
    createPlan = plan.createPlan,
    applyPlan = plan.applyPlan,
    revertPlan = plan.revertPlan,
}

local function getRuntimeKey(ownerId)
    if type(ownerId) ~= "string" or ownerId == "" then
        logging.violate("mutation.invalid_runtime_key", "mutation lifecycle requires ownerId")
    end
    return "owner:" .. ownerId, mutationState.ownerRuntime
end

local function getRuntimeState(ownerId)
    local key, bucket = getRuntimeKey(ownerId)
    return bucket[key], key, bucket
end

local function setRuntimeState(ownerId, state)
    local key, bucket = getRuntimeKey(ownerId)
    if state == nil or state.plan == nil then
        bucket[key] = nil
        return
    end
    bucket[key] = state
end

local function setActiveMutationPlan(ownerId, activePlan)
    local runtimeState = getRuntimeState(ownerId) or {}
    runtimeState.plan = activePlan
    setRuntimeState(ownerId, runtimeState)
end

local function captureActiveMutation(ownerId)
    local runtimeState = getRuntimeState(ownerId)
    if not runtimeState then
        return nil
    end
    return {
        plan = runtimeState.plan,
    }
end

local function hasActiveMutationSnapshot(snapshot)
    return snapshot and snapshot.plan ~= nil
end

local function restoreActiveMutation(ownerId, snapshot)
    if not hasActiveMutationSnapshot(snapshot) then
        return true, nil
    end

    local okPlan, errPlan = pcall(lifecycle.applyPlan, snapshot.plan)
    if not okPlan then
        return false, errPlan
    end

    setActiveMutationPlan(ownerId, snapshot.plan)
    return true, nil
end

local function buildMutationPlan(mutationBundle, authorHost, store)
    local builder = mutationBundle and mutationBundle.patchMutation
    if builder == nil then
        return nil
    end

    local mutationPlan = lifecycle.createPlan()
    builder(mutationPlan, authorHost, store)
    return mutationPlan
end

local function isEnabledForSync(def, store)
    local packId = def and def.modpack or nil
    local coord = packId and coordinator and coordinator.getConfig and coordinator.getConfig(packId) or nil
    if coord and not coord.ModEnabled then
        return false
    end
    if not store then
        return false
    end
    return store.read("Enabled") == true
end

local function revertActivePlan(ownerId)
    local runtimeState = getRuntimeState(ownerId)
    local activePlan = runtimeState and runtimeState.plan or nil
    if not activePlan then
        return true, nil, false
    end

    local okPlan, errPlan = pcall(lifecycle.revertPlan, activePlan)
    runtimeState.plan = nil
    setRuntimeState(ownerId, runtimeState)
    if not okPlan then
        return false, errPlan, true
    end
    return true, nil, true
end

local function hasPatchMutation(mutationBundle)
    return mutationBundle and type(mutationBundle.patchMutation) == "function" or false
end

function lifecycle.declarePatch(mutationBundle, callback)
    if type(callback) ~= "function" then
        logging.violate("mutation.invalid_registration", "host.mutation.patch: callback must be a function")
    end
    if type(mutationBundle) ~= "table" then
        logging.violate("mutation.invalid_registration", "host.mutation.patch: expected managed mutation bundle")
    end
    if mutationBundle.patchMutation ~= nil then
        logging.violate("mutation.invalid_registration", "host.mutation.patch: patch mutation already declared")
    end
    mutationBundle.patchMutation = callback
end

--- Returns whether a module declares that it affects live run data.
---@param mutationBundle table|nil Candidate mutation bundle.
---@return boolean affects True when the definition opts into run-data mutation behavior.
function lifecycle.affectsRunData(mutationBundle)
    return hasPatchMutation(mutationBundle)
end

--- Applies a module's current mutation lifecycle to live run data.
---@param ownerId string Stable owner id owning the active mutation slot.
---@param mutationBundle table|nil Module mutation callbacks.
---@param authorHost AuthorHost|nil Module author host passed to mutation builders.
---@param store AuthorStore|nil Author-facing module store associated with the definition.
---@return boolean ok True when the mutation lifecycle applied successfully.
---@return string|nil err Error message when the apply step fails.
function lifecycle.apply(ownerId, mutationBundle, authorHost, store)
    local hasPatch = hasPatchMutation(mutationBundle)
    local previousMutation = captureActiveMutation(ownerId)

    local okActive, errActive = revertActivePlan(ownerId)
    if not okActive then
        return false, errActive
    end

    local function failApply(err)
        if hasActiveMutationSnapshot(previousMutation) then
            local okRestore, restoreErr = restoreActiveMutation(ownerId, previousMutation)
            if not okRestore then
                return false, tostring(err) .. " (previous mutation restore failed: " .. tostring(restoreErr) .. ")"
            end
        end
        return false, err
    end

    if not hasPatch then
        return true, nil
    end

    local okBuild, result = pcall(buildMutationPlan, mutationBundle, authorHost, store)
    if not okBuild then
        return failApply(result)
    end
    local builtPlan = result
    if builtPlan then
        local okApply, errApply = pcall(lifecycle.applyPlan, builtPlan)
        if not okApply then
            return failApply(errApply)
        end
        setActiveMutationPlan(ownerId, builtPlan)
    end

    return true, nil
end

function lifecycle.sync(ownerId, def, mutationBundle, authorHost, store)
    local enabled = isEnabledForSync(def, store)
    local hasPatch = hasPatchMutation(mutationBundle)
    local candidatePlan = nil

    if enabled and hasPatch then
        candidatePlan = buildMutationPlan(mutationBundle, authorHost, store)
    end

    local previousMutation = captureActiveMutation(ownerId)
    local committed = false
    local disposed = false
    local revertedPrevious = false
    local appliedCandidate = false
    local setupRan = false

    local function restorePrevious(primaryErr, recompute)
        local rollbackErrors = {}

        if appliedCandidate and candidatePlan then
            local okRevert, errRevert = pcall(lifecycle.revertPlan, candidatePlan)
            if not okRevert then
                rollbackErrors[#rollbackErrors + 1] = "candidate revert failed: " .. tostring(errRevert)
            end
            setActiveMutationPlan(ownerId, nil)
            appliedCandidate = false
        end

        if hasActiveMutationSnapshot(previousMutation) then
            local okRestore, errRestore = restoreActiveMutation(ownerId, previousMutation)
            if not okRestore then
                rollbackErrors[#rollbackErrors + 1] = "previous mutation restore failed: " .. tostring(errRestore)
            end
        end

        if recompute then
            local okSetup, errSetup = pcall(setupRunData)
            if not okSetup then
                rollbackErrors[#rollbackErrors + 1] = "rollback recompute failed: " .. tostring(errSetup)
            end
        end

        if #rollbackErrors > 0 then
            if primaryErr ~= nil then
                return false, tostring(primaryErr) .. " (" .. table.concat(rollbackErrors, "; ") .. ")"
            end
            return false, table.concat(rollbackErrors, "; ")
        end
        if primaryErr ~= nil then
            return false, primaryErr
        end
        return true, nil
    end

    return {
        commit = function()
            if disposed or committed then
                return true, nil
            end

            local okRevert, errRevert, didRevert = revertActivePlan(ownerId)
            if not okRevert then
                return false, errRevert
            end
            revertedPrevious = didRevert == true

            if candidatePlan then
                local okApply, errApply = pcall(lifecycle.applyPlan, candidatePlan)
                if not okApply then
                    return restorePrevious(errApply, revertedPrevious)
                end
                setActiveMutationPlan(ownerId, candidatePlan)
                appliedCandidate = true
            end

            if revertedPrevious or appliedCandidate then
                local okSetup, errSetup = pcall(setupRunData)
                if not okSetup then
                    return restorePrevious(errSetup, true)
                end
                setupRan = true
            end

            committed = true
            return true, nil
        end,
        dispose = function()
            if disposed then
                return true, nil
            end
            if committed then
                local okRestore, errRestore = restorePrevious(nil, setupRan or revertedPrevious or appliedCandidate)
                disposed = true
                if not okRestore then
                    return false, errRestore
                end
                return true, nil
            end

            disposed = true
            return true, nil
        end,
    }
end

--- Reverts a module's current mutation lifecycle from live run data.
---@param ownerId string Stable owner id owning the active mutation slot.
---@return boolean ok True when the mutation lifecycle reverted successfully.
---@return string|nil err Error message when the revert step fails.
function lifecycle.revert(ownerId)
    local okPlan, errPlan = revertActivePlan(ownerId)
    if not okPlan then
        return false, errPlan
    end

    return true, nil
end

return lifecycle
