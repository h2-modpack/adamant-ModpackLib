local deps = ...

local logging = deps.logging
local CloneValue = deps.values.deepCopy
local requireMethodSelf = deps.requireMethodSelf

-- Per-import marker. Draw refs and the widgets that recognize them (`isDrawActionRef`) come
-- from the same Lib generation: a module's UI context captures the shared `draw` surface and its
-- action refs together at module creation, so refs never cross a Lib re-import boundary.
local ACTION_REF_MARKER = {}
local DRAW_ACTION_REF = "draw"
local COMMIT_ACTION_REF = "commit"

local function validateActionKey(context, actionKey)
    if type(actionKey) ~= "string" or actionKey == "" then
        logging.violate("actions.invalid_key", "%s: action key must be a non-empty string", tostring(context))
    end
end

local function isPrivateActionKey(actionKey)
    return type(actionKey) == "string" and string.byte(actionKey, 1) == 95
end

local function rejectPrivateActionKey(context, actionKey)
    if isPrivateActionKey(actionKey) then
        logging.violate(
            "actions.private_key",
            "%s: private Lib action key '%s' is not author-accessible",
            tostring(context),
            tostring(actionKey)
        )
    end
end

local function validateDeclaredAction(handlers, context, actionKey)
    validateActionKey(context, actionKey)
    if handlers[actionKey] == nil then
        logging.violate("actions.unknown_key", "%s: unknown action key '%s'", tostring(context), tostring(actionKey))
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

local function createDrawActionRef(actionBuffer, actionKey)
    local ref
    ref = markActionRef({
        stage = function(self, value)
            requireMethodSelf("actions.get(...):stage", self, ref)
            actionBuffer.stage(actionKey, value)
        end,
        read = function(self)
            requireMethodSelf("actions.get(...):read", self, ref)
            return actionBuffer.read(actionKey)
        end,
        clear = function(self)
            requireMethodSelf("actions.get(...):clear", self, ref)
            actionBuffer.clear(actionKey)
        end,
        has = function(self)
            requireMethodSelf("actions.get(...):has", self, ref)
            return actionBuffer.has(actionKey)
        end,
    }, DRAW_ACTION_REF)
    return ref
end

local function createDrawActionRefForKey(actionBuffer, actionKey)
    rejectPrivateActionKey("actions.get", actionKey)
    actionBuffer.validateAction("actions.get", actionKey)
    return createDrawActionRef(actionBuffer, actionKey)
end

local function createCommitActionRef(snapshot, actionKey)
    local ref
    ref = markActionRef({
        read = function(self)
            requireMethodSelf("commit.actions.get(...):read", self, ref)
            return CloneValue(snapshot[actionKey])
        end,
        has = function(self)
            requireMethodSelf("commit.actions.get(...):has", self, ref)
            return snapshot[actionKey] ~= nil
        end,
    }, COMMIT_ACTION_REF)
    return ref
end

---@param catalog { actions: table<string, function>, order: string[] } Prepared definition actions.
local function createBuffer(catalog)
    local handlers = catalog.actions
    local slots = {}
    local pendingEvents = {}
    local buffer = {}

    function buffer.stage(actionKey, value)
        validateDeclaredAction(handlers, "actions.stage", actionKey)
        if value == nil then
            slots[actionKey] = nil
            return
        end
        slots[actionKey] = CloneValue(value)
    end

    function buffer.validateAction(context, actionKey)
        validateDeclaredAction(handlers, context, actionKey)
    end

    function buffer.read(actionKey)
        validateDeclaredAction(handlers, "actions.read", actionKey)
        return CloneValue(slots[actionKey])
    end

    function buffer.clear(actionKey)
        validateDeclaredAction(handlers, "actions.clear", actionKey)
        slots[actionKey] = nil
    end

    function buffer.has(actionKey)
        validateDeclaredAction(handlers, "actions.has", actionKey)
        return slots[actionKey] ~= nil
    end

    function buffer.hasAny()
        return next(slots) ~= nil or #pendingEvents > 0
    end

    function buffer.captureSnapshot()
        return CloneValue(slots)
    end

    function buffer.clearAll()
        slots = {}
        pendingEvents = {}
    end

    function buffer.emitShared(id, eventName, payload)
        pendingEvents[#pendingEvents + 1] = {
            id = id,
            eventName = eventName,
            payload = CloneValue(payload),
        }
        return true, nil
    end

    function buffer.executeCommittedActions(host, runtime, actionSnapshot)
        for _, actionKey in ipairs(catalog.order) do
            if actionSnapshot and actionSnapshot[actionKey] ~= nil then
                handlers[actionKey](host, runtime, CloneValue(actionSnapshot[actionKey]))
            end
        end
    end

    function buffer.flushPendingSharedEvents(emitSharedEvent)
        if #pendingEvents > 0 then
            local events = pendingEvents
            pendingEvents = {}
            for _, event in ipairs(events) do
                emitSharedEvent(event.id, event.eventName, event.payload)
            end
        end
    end

    return buffer
end

local function createCommitActions(snapshot)
    snapshot = snapshot or {}
    local refs = {}

    return {
        get = function(actionKey)
            rejectPrivateActionKey("commit.actions.get", actionKey)
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
    createDrawActionRef = createDrawActionRefForKey,
    isDrawActionRef = isDrawActionRef,
}
