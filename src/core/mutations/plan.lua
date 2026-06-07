local deps = ...

local values = deps.values
local planExecutors = deps.planExecutors

local planApi = {}

function planApi.createBackup()
    local NIL = {}
    local savedValues = {}

    local function backup(tbl, ...)
        savedValues[tbl] = savedValues[tbl] or {}
        local saved = savedValues[tbl]
        for i = 1, select("#", ...) do
            local key = select(i, ...)
            if saved[key] == nil then
                local value = tbl[key]
                saved[key] = (value == nil) and NIL or values.deepCopy(value)
            end
        end
    end

    local function restore()
        for tbl, keys in pairs(savedValues) do
            for key, value in pairs(keys) do
                if value == NIL then
                    tbl[key] = nil
                elseif type(value) == "table" then
                    tbl[key] = values.deepCopy(value)
                else
                    tbl[key] = value
                end
            end
        end
        for tbl in pairs(savedValues) do
            savedValues[tbl] = nil
        end
    end

    return backup, restore
end

function planApi.createPlan()
    local backup, restore = planApi.createBackup()
    local operations = {}
    local applied = false
    local plan = {}

    local function appendOperation(op)
        operations[#operations + 1] = op
        return plan
    end

    function plan.set(_, tbl, key, value)
        return appendOperation({
            kind = "set",
            tbl = tbl,
            key = key,
            value = values.deepCopy(value),
        })
    end

    function plan.setMany(_, tbl, kv)
        return appendOperation({
            kind = "setMany",
            tbl = tbl,
            kv = kv,
        })
    end

    function plan.transform(_, tbl, key, fn)
        return appendOperation({
            kind = "transform",
            tbl = tbl,
            key = key,
            fn = fn,
        })
    end

    function plan.append(_, tbl, key, value)
        return appendOperation({
            kind = "append",
            tbl = tbl,
            key = key,
            value = values.deepCopy(value),
        })
    end

    function plan.appendUnique(_, tbl, key, value, equivalentFn)
        return appendOperation({
            kind = "appendUnique",
            tbl = tbl,
            key = key,
            value = values.deepCopy(value),
            equivalentFn = equivalentFn or values.deepEqual,
        })
    end

    function plan.removeElement(_, tbl, key, value, equivalentFn)
        return appendOperation({
            kind = "removeElement",
            tbl = tbl,
            key = key,
            value = values.deepCopy(value),
            equivalentFn = equivalentFn or values.deepEqual,
        })
    end

    function plan.setElement(_, tbl, key, oldValue, newValue, equivalentFn)
        return appendOperation({
            kind = "setElement",
            tbl = tbl,
            key = key,
            oldValue = values.deepCopy(oldValue),
            newValue = values.deepCopy(newValue),
            equivalentFn = equivalentFn or values.deepEqual,
        })
    end

    local function applyOperations()
        for _, op in ipairs(operations) do
            local tbl = op.tbl
            local key = op.key

            if op.kind == "set" then
                if tbl[key] ~= op.value then
                    backup(tbl, key)
                    tbl[key] = values.deepCopy(op.value)
                end
            elseif op.kind == "setMany" then
                for mapKey, value in pairs(op.kv) do
                    if tbl[mapKey] ~= value then
                        backup(tbl, mapKey)
                        tbl[mapKey] = values.deepCopy(value)
                    end
                end
            elseif op.kind == "transform" then
                backup(tbl, key)
                tbl[key] = values.deepCopy(op.fn(values.deepCopy(tbl[key])))
            elseif op.kind == "append" then
                local list = tbl[key]
                if list == nil then
                    backup(tbl, key)
                    list = {}
                    tbl[key] = list
                elseif type(list) ~= "table" then
                    error(("mutation plan append requires table at key '%s'"):format(tostring(key)), 0)
                else
                    backup(tbl, key)
                end
                list[#list + 1] = values.deepCopy(op.value)
            elseif op.kind == "appendUnique" then
                local list = tbl[key]
                if list == nil then
                    backup(tbl, key)
                    list = {}
                    tbl[key] = list
                elseif type(list) ~= "table" then
                    error(("mutation plan appendUnique requires table at key '%s'"):format(tostring(key)), 0)
                end

                local exists = false
                for _, entry in ipairs(list) do
                    if op.equivalentFn(entry, op.value) then
                        exists = true
                        break
                    end
                end
                if not exists then
                    backup(tbl, key)
                    list[#list + 1] = values.deepCopy(op.value)
                end
            elseif op.kind == "removeElement" then
                local list = tbl[key]
                if type(list) == "table" then
                    for index, entry in ipairs(list) do
                        if op.equivalentFn(entry, op.value) then
                            backup(tbl, key)
                            table.remove(list, index)
                            break
                        end
                    end
                elseif list ~= nil then
                    error(("mutation plan removeElement requires table at key '%s'"):format(tostring(key)), 0)
                end
            elseif op.kind == "setElement" then
                local list = tbl[key]
                if type(list) == "table" then
                    for index, entry in ipairs(list) do
                        if op.equivalentFn(entry, op.oldValue) then
                            backup(tbl, key)
                            list[index] = values.deepCopy(op.newValue)
                            break
                        end
                    end
                elseif list ~= nil then
                    error(("mutation plan setElement requires table at key '%s'"):format(tostring(key)), 0)
                end
            end
        end
    end

    local function applyPlan()
        if applied then
            return false
        end

        local ok, err = pcall(applyOperations)
        if not ok then
            restore()
            error(err, 0)
        end

        applied = true
        return true
    end

    local function revertPlan()
        if not applied then
            return false
        end
        restore()
        applied = false
        return true
    end

    planExecutors[plan] = {
        apply = applyPlan,
        revert = revertPlan,
    }

    return plan --[[@as MutationPlan]]
end

local function getPlanExecutor(plan, action)
    local executor = planExecutors[plan]
    if not executor then
        error("mutation plan is not executable", 0)
    end
    return executor[action]
end

function planApi.applyPlan(plan)
    return getPlanExecutor(plan, "apply")()
end

function planApi.revertPlan(plan)
    return getPlanExecutor(plan, "revert")()
end

return planApi
