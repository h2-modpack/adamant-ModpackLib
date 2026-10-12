-- Stateless constructor for capability install receipts.
--
-- A receipt wraps one capability install that activation can commit, roll back,
-- or retire. Callbacks may return `false, err` or raise; the receipt pcall-wraps
-- them so callers only see `ok, err`.
--
-- Lifecycle:
-- - `commit()` runs once. Repeating it after success is a no-op; committing a
--   released receipt is an error.
-- - `rollback()` undoes this install and restores what it replaced (activation
--   failure path).
-- - `retire()` removes only what this install still owns and never restores
--   replaced state (old-module retirement after a successor committed).
-- - Rollback/retire run at most once; the receipt is released afterwards and
--   further calls are no-op successes.
-- - On an uncommitted receipt (never committed, or commit failed) both run the
--   optional `discard` callback instead, which drops install-time staging or a
--   failed commit's partial application. Without `discard` they are no-ops.
--   A failed commit must be followed by `rollback()`.

local receipt = {}

-- Commit phases: game-data mutations commit before the effects that observe them.
receipt.PHASE_GAME_DATA = 1
receipt.PHASE_EFFECTS = 2

---@class AdamantModpackLib.ReceiptSpec
---@field name string
---@field phase integer
---@field commit fun(): boolean?, string?
---@field rollback fun(): boolean?, string?
---@field retire fun(): boolean?, string?
---@field discard? fun(): boolean?, string?

---@class AdamantModpackLib.Receipt
---@field name string
---@field phase integer
---@field commit fun(): boolean, string?
---@field rollback fun(): boolean, string?
---@field retire fun(): boolean, string?

local function call(callback)
    local ok, result, err = pcall(callback)
    if not ok then
        return false, result
    end
    if result == false then
        return false, err
    end
    return true, nil
end

---@param spec AdamantModpackLib.ReceiptSpec
---@return AdamantModpackLib.Receipt
function receipt.create(spec)
    local state = "pending"

    local function release(callback)
        if state == "released" then
            return true, nil
        end
        if state ~= "committed" then
            callback = spec.discard
        end
        state = "released"
        if callback == nil then
            return true, nil
        end
        return call(callback)
    end

    return {
        name = spec.name,
        phase = spec.phase,
        commit = function()
            if state == "committed" then
                return true, nil
            end
            if state == "released" then
                return false, tostring(spec.name) .. " receipt is already released"
            end
            local ok, err = call(spec.commit)
            state = ok and "committed" or "failed"
            return ok, err
        end,
        rollback = function()
            return release(spec.rollback)
        end,
        retire = function()
            return release(spec.retire)
        end,
    }
end

local function succeed()
    return true, nil
end

---@param name string
---@param phase integer
---@return AdamantModpackLib.Receipt
function receipt.noop(name, phase)
    return receipt.create({
        name = name,
        phase = phase,
        commit = succeed,
        rollback = succeed,
        retire = succeed,
    })
end

local function releaseChildren(children, methodName)
    local firstErr = nil
    for index = #children, 1, -1 do
        local ok, err = children[index][methodName]()
        if not ok and firstErr == nil then
            firstErr = tostring(children[index].name) .. ": " .. tostring(err)
        end
    end
    if firstErr ~= nil then
        return false, firstErr
    end
    return true, nil
end

--- Commits children in order and releases them in reverse. A failed child commit
--- leaves the composite uncommitted; its rollback then releases every child.
---@param name string
---@param phase integer
---@param children AdamantModpackLib.Receipt[]
---@return AdamantModpackLib.Receipt
function receipt.composite(name, phase, children)
    local function rollbackChildren()
        return releaseChildren(children, "rollback")
    end
    return receipt.create({
        name = name,
        phase = phase,
        commit = function()
            for _, child in ipairs(children) do
                local ok, err = child.commit()
                if not ok then
                    return false, tostring(child.name) .. ": " .. tostring(err)
                end
            end
            return true, nil
        end,
        rollback = rollbackChildren,
        retire = function()
            return releaseChildren(children, "retire")
        end,
        discard = rollbackChildren,
    })
end

return receipt
