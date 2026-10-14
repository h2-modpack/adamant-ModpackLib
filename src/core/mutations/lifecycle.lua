local deps = ...

local logging = deps.logging
local setupRunData = deps.setupRunData
local ownerSlots = deps.ownerSlots
local plan = deps.plan
local receipt = deps.receipt

local lifecycle = {}

-- `ownerSlots` is a hot-reload anchor: a Lib re-import must find (and be able to revert) plans
-- the previous import applied. Keep its key format (`"owner:" .. ownerId`) and slot shape
-- (`{ plan = activePlan }`) stable, or a reload orphans an applied plan.
local function slotKey(ownerId)
    return "owner:" .. ownerId
end

local function getActivePlan(ownerId)
    local slot = ownerSlots[slotKey(ownerId)]
    return slot and slot.plan or nil
end

local function setActivePlan(ownerId, activePlan)
    ownerSlots[slotKey(ownerId)] = activePlan and { plan = activePlan } or nil
end

-- Re-applies a plan captured before a failed change and makes it active again.
local function restoreActivePlan(ownerId, previousPlan)
    if previousPlan == nil then
        return true, nil
    end

    local okPlan, errPlan = pcall(plan.applyPlan, previousPlan)
    if not okPlan then
        return false, errPlan
    end

    setActivePlan(ownerId, previousPlan)
    return true, nil
end

local function buildMutationPlan(mutationBundle, runtime, host)
    local builder = mutationBundle.patchMutation
    if builder == nil then
        return nil
    end

    local mutationPlan = plan.createPlan()
    builder(host, runtime, mutationPlan)
    return mutationPlan
end

local function isEnabledForSync(runtime)
    return runtime.data.read("Enabled") == true
end

local function revertActivePlan(ownerId)
    local activePlan = getActivePlan(ownerId)
    if not activePlan then
        return true, nil, false
    end

    local okPlan, errPlan = pcall(plan.revertPlan, activePlan)
    setActivePlan(ownerId, nil)
    if not okPlan then
        return false, errPlan, true
    end
    return true, nil, true
end

local function hasPatchMutation(mutationBundle)
    return mutationBundle.patchMutation ~= nil
end

function lifecycle.declarePatch(mutationBundle, callback)
    if type(callback) ~= "function" then
        logging.violate("mutation.invalid_registration", "module.mutation.patch: callback must be a function")
    end
    if mutationBundle.patchMutation ~= nil then
        logging.violate("mutation.invalid_registration", "module.mutation.patch: patch mutation already declared")
    end
    mutationBundle.patchMutation = callback
end

local function apply(ownerId, mutationBundle, runtime, host)
    local hasPatch = hasPatchMutation(mutationBundle)
    local previousPlan = getActivePlan(ownerId)

    local okActive, errActive = revertActivePlan(ownerId)
    if not okActive then
        return false, errActive
    end

    local function failApply(err)
        local okRestore, restoreErr = restoreActivePlan(ownerId, previousPlan)
        if not okRestore then
            return false, tostring(err) .. " (previous mutation restore failed: " .. tostring(restoreErr) .. ")"
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
        setActivePlan(ownerId, builtPlan)
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

    local previousPlan = getActivePlan(ownerId)
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
            setActivePlan(ownerId, nil)
            appliedCandidate = false
        end

        local okRestore, errRestore = restoreActivePlan(ownerId, previousPlan)
        if not okRestore then
            rollbackErrors[#rollbackErrors + 1] = "previous mutation restore failed: " .. tostring(errRestore)
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
                setActivePlan(ownerId, candidatePlan)
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
