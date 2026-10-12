local deps = ...

local logging = deps.logging
local setupRunData = deps.setupRunData
local mutationRegistry = deps.mutationRegistry
local plan = deps.plan
local receipt = deps.receipt

local lifecycle = {}

local function getMutationSlotKey(ownerId)
    if type(ownerId) ~= "string" or ownerId == "" then
        logging.violate("mutation.invalid_runtime_key", "mutation lifecycle requires ownerId")
    end
    return "owner:" .. ownerId, mutationRegistry.ownerSlots
end

local function getMutationSlot(ownerId)
    local key, bucket = getMutationSlotKey(ownerId)
    return bucket[key], key, bucket
end

local function setMutationSlot(ownerId, slot)
    local key, bucket = getMutationSlotKey(ownerId)
    if slot == nil or slot.plan == nil then
        bucket[key] = nil
        return
    end
    bucket[key] = slot
end

local function setActiveMutationPlan(ownerId, activePlan)
    local slot = getMutationSlot(ownerId) or {}
    slot.plan = activePlan
    setMutationSlot(ownerId, slot)
end

local function captureActiveMutation(ownerId)
    local slot = getMutationSlot(ownerId)
    if not slot then
        return nil
    end
    return {
        plan = slot.plan,
    }
end

local function hasActiveMutationSnapshot(snapshot)
    return snapshot and snapshot.plan ~= nil
end

local function restoreActiveMutation(ownerId, snapshot)
    if not hasActiveMutationSnapshot(snapshot) then
        return true, nil
    end

    local okPlan, errPlan = pcall(plan.applyPlan, snapshot.plan)
    if not okPlan then
        return false, errPlan
    end

    setActiveMutationPlan(ownerId, snapshot.plan)
    return true, nil
end

local function buildMutationPlan(mutationBundle, runtime, host)
    local builder = mutationBundle and mutationBundle.patchMutation
    if builder == nil then
        return nil
    end

    local mutationPlan = plan.createPlan()
    builder(host, runtime, mutationPlan)
    return mutationPlan
end

local function isEnabledForSync(runtime)
    if not (runtime and runtime.data) then
        return false
    end
    return runtime.data.read("Enabled") == true
end

local function revertActivePlan(ownerId)
    local slot = getMutationSlot(ownerId)
    local activePlan = slot and slot.plan or nil
    if not activePlan then
        return true, nil, false
    end

    local okPlan, errPlan = pcall(plan.revertPlan, activePlan)
    slot.plan = nil
    setMutationSlot(ownerId, slot)
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
        logging.violate("mutation.invalid_registration", "module.mutation.patch: callback must be a function")
    end
    if type(mutationBundle) ~= "table" then
        logging.violate("mutation.invalid_registration", "module.mutation.patch: expected managed mutation bundle")
    end
    if mutationBundle.patchMutation ~= nil then
        logging.violate("mutation.invalid_registration", "module.mutation.patch: patch mutation already declared")
    end
    mutationBundle.patchMutation = callback
end

local function apply(ownerId, mutationBundle, runtime, host)
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

    local okBuild, result = pcall(buildMutationPlan, mutationBundle, runtime, host)
    if not okBuild then
        return failApply(result)
    end
    local builtPlan = result
    if builtPlan then
        local okApply, errApply = pcall(plan.applyPlan, builtPlan)
        if not okApply then
            return failApply(errApply)
        end
        setActiveMutationPlan(ownerId, builtPlan)
    end

    return true, nil
end

local function sync(ownerId, mutationBundle, runtime, host)
    local enabled = isEnabledForSync(runtime)
    local hasPatch = hasPatchMutation(mutationBundle)
    local candidatePlan = nil

    if enabled and hasPatch then
        candidatePlan = buildMutationPlan(mutationBundle, runtime, host)
    end

    local previousMutation = captureActiveMutation(ownerId)
    local revertedPrevious = false
    local appliedCandidate = false
    local setupRan = false

    local function restorePrevious(primaryErr, recompute)
        local rollbackErrors = {}

        if appliedCandidate and candidatePlan then
            local okRevert, errRevert = pcall(plan.revertPlan, candidatePlan)
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

    return receipt.create({
        name = "mutation",
        phase = receipt.PHASE_GAME_DATA,
        -- A failed commit restores the previous plan itself, so no discard is needed.
        commit = function()
            local okRevert, errRevert, didRevert = revertActivePlan(ownerId)
            if not okRevert then
                return false, errRevert
            end
            revertedPrevious = didRevert == true

            if candidatePlan then
                local okApply, errApply = pcall(plan.applyPlan, candidatePlan)
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

            return true, nil
        end,
        rollback = function()
            return restorePrevious(nil, setupRan or revertedPrevious or appliedCandidate)
        end,
        -- The owner's active-plan slot is process-global: a successor's sync commit already
        -- reverted this install's plan and replaced the slot, so there is nothing left to retire.
        retire = function()
            return true, nil
        end,
    })
end

local function revert(ownerId)
    local okPlan, errPlan = revertActivePlan(ownerId)
    if not okPlan then
        return false, errPlan
    end

    return true, nil
end

--- Binds one owner's mutation bundle to the host/runtime its patch builder receives.
---
--- Ownership of the run-data recompute (`SetupRunData`):
--- - `sync()` returns an activation receipt that recomputes run data itself on commit, and on
---   rollback whenever it changed the active plan.
--- - `apply()` / `revert()` change the active plan only; the caller owns the recompute
---   (commit flows mark run data dirty and the pack/fallback UI flushes it).
---@param ownerId string
---@param mutationBundle AdamantModpackLib.MutationBundle
---@param host AdamantModpackLib.Host
---@param runtime AdamantModpackLib.RuntimeContext
---@return AdamantModpackLib.BoundMutation
function lifecycle.bind(ownerId, mutationBundle, host, runtime)
    getMutationSlotKey(ownerId)
    return {
        apply = function()
            return apply(ownerId, mutationBundle, runtime, host)
        end,
        revert = function()
            return revert(ownerId)
        end,
        sync = function()
            return sync(ownerId, mutationBundle, runtime, host)
        end,
        affectsRunData = function()
            return hasPatchMutation(mutationBundle)
        end,
    }
end

return lifecycle
