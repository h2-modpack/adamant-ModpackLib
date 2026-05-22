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

local function requireRefSelf(context, self, ref)
    if self ~= ref then
        logging.violate("api.invalid_method_call", "%s must be called with ':' method syntax", context)
    end
end

local function createDrawActionRef(actionBuffer, actionKey)
    local ref
    ref = markActionRef({
        stage = function(self, value)
            requireRefSelf("actions.get(...):stage", self, ref)
            actionBuffer.stage(actionKey, value)
        end,
        read = function(self)
            requireRefSelf("actions.get(...):read", self, ref)
            return actionBuffer.read(actionKey)
        end,
        clear = function(self)
            requireRefSelf("actions.get(...):clear", self, ref)
            actionBuffer.clear(actionKey)
        end,
        has = function(self)
            requireRefSelf("actions.get(...):has", self, ref)
            return actionBuffer.has(actionKey)
        end,
    }, DRAW_ACTION_REF)
    return ref
end

local function createCommitActionRef(snapshot, actionKey)
    local ref
    ref = markActionRef({
        read = function(self)
            requireRefSelf("commit.actions.get(...):read", self, ref)
            return CloneValue(snapshot[actionKey])
        end,
        has = function(self)
            requireRefSelf("commit.actions.get(...):has", self, ref)
            return snapshot[actionKey] ~= nil
        end,
    }, COMMIT_ACTION_REF)
    return ref
end

local function createBuffer()
    local slots = {}
    local refs = {}
    local buffer = {}

    function buffer.stage(actionKey, value)
        validateActionKey("actions.stage", actionKey)
        if value == nil then
            slots[actionKey] = nil
            return
        end
        slots[actionKey] = CloneValue(value)
    end

    function buffer.read(actionKey)
        validateActionKey("actions.read", actionKey)
        return CloneValue(slots[actionKey])
    end

    function buffer.clear(actionKey)
        validateActionKey("actions.clear", actionKey)
        slots[actionKey] = nil
    end

    function buffer.has(actionKey)
        validateActionKey("actions.has", actionKey)
        return slots[actionKey] ~= nil
    end

    function buffer.hasAny()
        return next(slots) ~= nil
    end

    function buffer.captureSnapshot()
        return CloneValue(slots)
    end

    function buffer.clearAll()
        slots = {}
    end

    function buffer.getRef(actionKey)
        validateActionKey("actions.get", actionKey)
        local ref = refs[actionKey]
        if ref ~= nil then
            return ref
        end
        ref = createDrawActionRef(buffer, actionKey)
        refs[actionKey] = ref
        return ref
    end

    return buffer
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
    createBuffer = createBuffer,
    createCommitActions = createCommitActions,
    isDrawActionRef = isDrawActionRef,
}
