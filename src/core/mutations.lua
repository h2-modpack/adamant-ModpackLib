public.mutation = public.mutation or {}
local mutation = public.mutation
local mutationRuntime = setmetatable({}, { __mode = "k" })

---@alias MutationShape "patch"|"manual"|"hybrid"

---@class MutationInfo
---@field hasPatch boolean
---@field hasApply boolean
---@field hasRevert boolean
---@field hasManual boolean

---@class MutationPlan
---@field set fun(self: MutationPlan, tbl: table, key: any, value: any): MutationPlan
---@field setMany fun(self: MutationPlan, tbl: table, kv: table): MutationPlan
---@field transform fun(self: MutationPlan, tbl: table, key: any, fn: fun(current: any, key: any, tbl: table): any): MutationPlan
---@field append fun(self: MutationPlan, tbl: table, key: any, value: any): MutationPlan
---@field appendUnique fun(self: MutationPlan, tbl: table, key: any, value: any, equivalentFn: fun(a: any, b: any): boolean|nil): MutationPlan
---@field removeElement fun(self: MutationPlan, tbl: table, key: any, value: any, equivalentFn: fun(a: any, b: any): boolean|nil): MutationPlan
---@field setElement fun(self: MutationPlan, tbl: table, key: any, oldValue: any, newValue: any, equivalentFn: fun(a: any, b: any): boolean|nil): MutationPlan
---@field apply fun(): boolean
---@field revert fun(): boolean

local function CloneMutationValue(value)
    if type(value) == "table" then
        return rom.game.DeepCopyTable(value)
    end
    return value
end

local function MutationDeepEqual(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end

    for key, value in pairs(a) do
        if not MutationDeepEqual(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

local function GetActiveMutationPlan(store)
    local runtime = store and mutationRuntime[store]
    return runtime and runtime.plan or nil
end

local function SetActiveMutationPlan(store, plan)
    if not store then
        return
    end
    if plan == nil then
        mutationRuntime[store] = nil
        return
    end
    mutationRuntime[store] = { plan = plan }
end

local function BuildMutationPlan(def, store)
    local builder = def and def.patchPlan
    if type(builder) ~= "function" then
        return nil
    end

    local plan = mutation.createPlan()
    builder(plan, store)
    return plan
end

--- Infers which mutation lifecycle a module definition exposes.
---@param def ModuleDefinition Candidate module definition table.
---@return MutationShape|nil shape Inferred lifecycle shape: `patch`, `manual`, `hybrid`, or nil.
---@return MutationInfo info Flags describing which lifecycle hooks are present on the definition.
function mutation.inferShape(def)
    local hasPatch = def and type(def.patchPlan) == "function" or false
    local hasApply = def and type(def.apply) == "function" or false
    local hasRevert = def and type(def.revert) == "function" or false
    local hasManual = hasApply and hasRevert

    local inferred = nil
    if hasPatch and hasManual then
        inferred = "hybrid"
    elseif hasPatch then
        inferred = "patch"
    elseif hasManual then
        inferred = "manual"
    end

    return inferred, {
        hasPatch = hasPatch,
        hasApply = hasApply,
        hasRevert = hasRevert,
        hasManual = hasManual,
    }
end

--- Returns whether a module definition declares that it mutates live run data.
---@param def ModuleDefinition|nil Candidate module definition table.
---@return boolean mutates True when the definition opts into run-data mutation behavior.
function mutation.mutatesRunData(def)
    if not def then
        return false
    end
    return def.affectsRunData == true
end


--- Creates backup and restore helpers for reversible table mutations.
---@return function backup Captures original values on a table before mutation.
---@return function restore Restores all captured values back onto their original tables.
function mutation.createBackup()
    local NIL = {}
    local savedValues = {}

    local function backup(tbl, ...)
        savedValues[tbl] = savedValues[tbl] or {}
        local saved = savedValues[tbl]
        for i = 1, select("#", ...) do
            local key = select(i, ...)
            if saved[key] == nil then
                local v = tbl[key]
                saved[key] = (v == nil) and NIL or (type(v) == "table" and rom.game.DeepCopyTable(v) or v)
            end
        end
    end

    local function restore()
        for tbl, keys in pairs(savedValues) do
            for key, v in pairs(keys) do
                if v == NIL then
                    tbl[key] = nil
                elseif type(v) == "table" then
                    tbl[key] = rom.game.DeepCopyTable(v)
                else
                    tbl[key] = v
                end
            end
        end
    end

    return backup, restore
end

--- Creates a reversible mutation plan that can batch table updates and roll them back later.
---@return MutationPlan plan Mutable mutation plan with operation builders plus apply/revert methods.
function mutation.createPlan()
    local backup, restore = mutation.createBackup()
    local operations = {}
    local applied = false
    local plan = {}

    local function appendOperation(op)
        operations[#operations + 1] = op
        return plan
    end

    --- Queues a direct table assignment inside the mutation plan.
    ---@param _ table Mutation plan receiver.
    ---@param tbl table Target table to mutate.
    ---@param key any Key to assign on the target table.
    ---@param value any Value to assign at the target key.
    ---@return table plan The same mutation plan for chaining.
    function plan.set(_, tbl, key, value)
        return appendOperation({
            kind = "set",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
        })
    end

    --- Queues multiple table assignments inside the mutation plan.
    ---@param _ table Mutation plan receiver.
    ---@param tbl table Target table to mutate.
    ---@param kv table Key/value map to assign on the target table.
    ---@return table plan The same mutation plan for chaining.
    function plan.setMany(_, tbl, kv)
        return appendOperation({
            kind = "setMany",
            tbl = tbl,
            kv = kv,
        })
    end

    --- Queues a transform function that replaces a single table value during apply.
    ---@param _ table Mutation plan receiver.
    ---@param tbl table Target table to mutate.
    ---@param key any Key to transform on the target table.
    ---@param fn function Transform function receiving the current value, key, and table.
    ---@return table plan The same mutation plan for chaining.
    function plan.transform(_, tbl, key, fn)
        return appendOperation({
            kind = "transform",
            tbl = tbl,
            key = key,
            fn = fn,
        })
    end

    --- Queues an append into a list-valued table field.
    ---@param _ table Mutation plan receiver.
    ---@param tbl table Target table to mutate.
    ---@param key any Key whose value should be treated as a list.
    ---@param value any Value to append into the list.
    ---@return table plan The same mutation plan for chaining.
    function plan.append(_, tbl, key, value)
        return appendOperation({
            kind = "append",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
        })
    end

    --- Queues an append that only runs when no equivalent list element already exists.
    ---@param _ table Mutation plan receiver.
    ---@param tbl table Target table to mutate.
    ---@param key any Key whose value should be treated as a list.
    ---@param value any Value to append into the list.
    ---@param equivalentFn function|nil Optional equality predicate for comparing list entries.
    ---@return table plan The same mutation plan for chaining.
    function plan.appendUnique(_, tbl, key, value, equivalentFn)
        return appendOperation({
            kind = "appendUnique",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
            equivalentFn = equivalentFn or MutationDeepEqual,
        })
    end

    --- Queues removal of the first equivalent element from a list-valued table field.
    ---@param _ table Mutation plan receiver.
    ---@param tbl table Target table to mutate.
    ---@param key any Key whose value should be treated as a list.
    ---@param value any Value to remove from the list.
    ---@param equivalentFn function|nil Optional equality predicate for comparing list entries.
    ---@return table plan The same mutation plan for chaining.
    function plan.removeElement(_, tbl, key, value, equivalentFn)
        return appendOperation({
            kind = "removeElement",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
            equivalentFn = equivalentFn or MutationDeepEqual,
        })
    end

    --- Queues replacement of the first equivalent element in a list-valued table field.
    ---@param _ table Mutation plan receiver.
    ---@param tbl table Target table to mutate.
    ---@param key any Key whose value should be treated as a list.
    ---@param oldValue any Value to match for replacement.
    ---@param newValue any Replacement value to write into the list.
    ---@param equivalentFn function|nil Optional equality predicate for comparing list entries.
    ---@return table plan The same mutation plan for chaining.
    function plan.setElement(_, tbl, key, oldValue, newValue, equivalentFn)
        return appendOperation({
            kind = "setElement",
            tbl = tbl,
            key = key,
            oldValue = CloneMutationValue(oldValue),
            newValue = CloneMutationValue(newValue),
            equivalentFn = equivalentFn or MutationDeepEqual,
        })
    end

    --- Applies all queued mutation plan operations in order.
    ---@return boolean applied True when the plan was applied during this call.
    function plan.apply()
        if applied then
            return false
        end

        for _, op in ipairs(operations) do
            local tbl = op.tbl
            local key = op.key

            if op.kind == "set" then
                if tbl[key] ~= op.value then
                    backup(tbl, key)
                    tbl[key] = CloneMutationValue(op.value)
                end
            elseif op.kind == "setMany" then
                for mapKey, value in pairs(op.kv) do
                    if tbl[mapKey] ~= value then
                        backup(tbl, mapKey)
                        tbl[mapKey] = CloneMutationValue(value)
                    end
                end
            elseif op.kind == "transform" then
                backup(tbl, key)
                tbl[key] = op.fn(tbl[key], key, tbl)
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
                list[#list + 1] = CloneMutationValue(op.value)
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
                    list[#list + 1] = CloneMutationValue(op.value)
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
                            list[index] = CloneMutationValue(op.newValue)
                            break
                        end
                    end
                elseif list ~= nil then
                    error(("mutation plan setElement requires table at key '%s'"):format(tostring(key)), 0)
                end
            end
        end

        applied = true
        return true
    end

    --- Reverts the last successful application of the mutation plan.
    ---@return boolean reverted True when the plan was reverted during this call.
    function plan.revert()
        if not applied then
            return false
        end
        restore()
        applied = false
        return true
    end

    return plan
end

--- Applies a module definition's current mutation lifecycle to live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle applied successfully.
---@return string|nil err Error message when the apply step fails.
function mutation.apply(def, store)
    local inferred, info = mutation.inferShape(def)
    if not inferred then
        if not mutation.mutatesRunData(def) then
            return true, nil
        end
        return false, "no supported mutation lifecycle found"
    end

    local activePlan = GetActiveMutationPlan(store)
    if activePlan then
        local okRevert, errRevert = pcall(activePlan.revert, activePlan)
        if not okRevert then
            return false, errRevert
        end
        SetActiveMutationPlan(store, nil)
    end

    local builtPlan = nil
    if info.hasPatch then
        local okBuild, result = pcall(BuildMutationPlan, def, store)
        if not okBuild then
            return false, result
        end
        builtPlan = result
        if builtPlan then
            local okApply, errApply = pcall(builtPlan.apply, builtPlan)
            if not okApply then
                return false, errApply
            end
            SetActiveMutationPlan(store, builtPlan)
        end
    end

    if info.hasManual then
        local okManual, errManual = pcall(def.apply)
        if not okManual then
            if builtPlan then
                pcall(builtPlan.revert, builtPlan)
                SetActiveMutationPlan(store, nil)
            end
            return false, errManual
        end
    end

    return true, nil
end

--- Reverts a module definition's current mutation lifecycle from live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reverted successfully.
---@return string|nil err Error message when the revert step fails.
function mutation.revert(def, store)
    local inferred, info = mutation.inferShape(def)
    if not inferred then
        if not mutation.mutatesRunData(def) then
            return true, nil
        end
        return false, "no supported mutation lifecycle found"
    end

    local firstErr = nil

    if info.hasManual then
        local okManual, errManual = pcall(def.revert)
        if not okManual and not firstErr then
            firstErr = errManual
        end
    end

    local activePlan = GetActiveMutationPlan(store)
    if activePlan then
        local okPlan, errPlan = pcall(activePlan.revert, activePlan)
        SetActiveMutationPlan(store, nil)
        if not okPlan and not firstErr then
            firstErr = errPlan
        end
    end

    if firstErr then
        return false, firstErr
    end

    return true, nil
end

--- Sets the enabled state for a mutating module and applies or reverts live changes as needed.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore Managed module store associated with the definition.
---@param enabled boolean Desired enabled state.
---@return boolean ok True when the enabled state transition completed successfully.
---@return string|nil err Error message when the transition fails.
function mutation.setEnabled(def, store, enabled)
    local current = store and type(store.read) == "function" and store.read("Enabled") == true or false

    local ok, err
    if enabled and current then
        ok, err = mutation.reapply(def, store)
    elseif enabled then
        ok, err = mutation.apply(def, store)
    elseif current then
        ok, err = mutation.revert(def, store)
    else
        ok, err = true, nil
    end

    if not ok then
        return false, err
    end

    store.write("Enabled", enabled)
    return true, nil
end

--- Reverts and reapplies a module definition's mutation lifecycle.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reapplied successfully.
---@return string|nil err Error message when the reapply step fails.
function mutation.reapply(def, store)
    local okRevert, errRevert = mutation.revert(def, store)
    if not okRevert then
        return false, errRevert
    end

    local okApply, errApply = mutation.apply(def, store)
    if not okApply then
        return false, errApply
    end

    return true, nil
end
