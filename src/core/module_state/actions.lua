local deps = ...

local logging = deps.logging
local CloneValue = deps.values.deepCopy

local ACTION_REF_MARKER = {}
local DRAW_ACTION_REF = "draw"
local COMMIT_ACTION_REF = "commit"

local function validateActionKey(context, actionKey)
    if type(actionKey) ~= "string" or actionKey == "" then
        logging.violate("actions.invalid_key", "%s: action key must be a non-empty string", tostring(context))
    end
end

local function markActionRef(ref, kind)
    ref[ACTION_REF_MARKER] = kind
    return ref
end

local function actionRefKind(value)
    if type(value) ~= "table" then
        return nil
    end
    return value[ACTION_REF_MARKER]
end

local function isDrawActionRef(value)
    return actionRefKind(value) == DRAW_ACTION_REF
end

local function createDrawActionRef(actionState, actionKey)
    local ref
    ref = markActionRef({
        stage = function(self, value)
            if self ~= ref then
                value = self
            end
            actionState.stage(actionKey, value)
        end,
        read = function()
            return actionState.read(actionKey)
        end,
        clear = function()
            actionState.clear(actionKey)
        end,
        has = function()
            return actionState.has(actionKey)
        end,
    }, DRAW_ACTION_REF)
    return ref
end

local function createCommitActionRef(snapshot, actionKey)
    return markActionRef({
        read = function()
            return CloneValue(snapshot[actionKey])
        end,
        has = function()
            return snapshot[actionKey] ~= nil
        end,
    }, COMMIT_ACTION_REF)
end

local function createState()
    local slots = {}
    local refs = {}
    local state = {}

    function state.stage(actionKey, value)
        validateActionKey("session.stageAction", actionKey)
        if value == nil then
            slots[actionKey] = nil
            return
        end
        slots[actionKey] = CloneValue(value)
    end

    function state.read(actionKey)
        validateActionKey("session.readAction", actionKey)
        return CloneValue(slots[actionKey])
    end

    function state.clear(actionKey)
        validateActionKey("session.clearAction", actionKey)
        slots[actionKey] = nil
    end

    function state.has(actionKey)
        validateActionKey("actions.has", actionKey)
        return slots[actionKey] ~= nil
    end

    function state.hasAny()
        return next(slots) ~= nil
    end

    function state.captureSnapshot()
        return CloneValue(slots)
    end

    function state.clearAll()
        slots = {}
    end

    function state.getRef(actionKey)
        validateActionKey("actions.get", actionKey)
        local ref = refs[actionKey]
        if ref ~= nil then
            return ref
        end
        ref = createDrawActionRef(state, actionKey)
        refs[actionKey] = ref
        return ref
    end

    return state
end

local function createDrawActions(actionState)
    return {
        get = function(actionKey)
            return actionState.getRef(actionKey)
        end,
        hasAny = function()
            return actionState.hasAny()
        end,
    }
end

local function createCommitActions(snapshot)
    snapshot = snapshot or {}
    local refs = {}

    return {
        get = function(actionKey)
            validateActionKey("commit.actions.get", actionKey)
            local ref = refs[actionKey]
            if ref ~= nil then
                return ref
            end
            ref = createCommitActionRef(snapshot, actionKey)
            refs[actionKey] = ref
            return ref
        end,
        hasAny = function()
            return next(snapshot) ~= nil
        end,
    }
end

return {
    createState = createState,
    createDrawActions = createDrawActions,
    createCommitActions = createCommitActions,
    isDrawActionRef = isDrawActionRef,
}
