local deps = ...

local logging = deps.logging
local CloneValue = deps.values.deepCopy

local ACTION_REF_MARKER = {}
local DRAW_ACTION_REF = "draw"
local COMMIT_ACTION_REF = "commit"

local function createActionCatalog(actions, actionOrder)
    local handlers = actions or {}
    local order = actionOrder or {}
    return {
        handlers = handlers,
        order = order,
    }
end

local function validateActionKey(context, actionKey)
    if type(actionKey) ~= "string" or actionKey == "" then
        logging.violate("actions.invalid_key", "%s: action key must be a non-empty string", tostring(context))
    end
end

local function validateDeclaredAction(catalog, context, actionKey)
    validateActionKey(context, actionKey)
    if catalog ~= nil and catalog.handlers[actionKey] == nil then
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

local function requireRefSelf(context, self, ref)
    if self ~= ref then
        logging.violate("api.invalid_method_call", "%s must be called with ':' method syntax", context)
    end
end

local function createDrawActionRef(actionBuffer, actionKey, phaseGate)
    local ref
    ref = markActionRef({
        stage = function(self, value)
            requireRefSelf("actions.get(...):stage", self, ref)
            if phaseGate ~= nil then
                phaseGate.requireAnyDraw()
            end
            actionBuffer.stage(actionKey, value)
        end,
        read = function(self)
            requireRefSelf("actions.get(...):read", self, ref)
            if phaseGate ~= nil then
                phaseGate.requireAnyDraw()
            end
            return actionBuffer.read(actionKey)
        end,
        clear = function(self)
            requireRefSelf("actions.get(...):clear", self, ref)
            if phaseGate ~= nil then
                phaseGate.requireAnyDraw()
            end
            actionBuffer.clear(actionKey)
        end,
        has = function(self)
            requireRefSelf("actions.get(...):has", self, ref)
            if phaseGate ~= nil then
                phaseGate.requireAnyDraw()
            end
            return actionBuffer.has(actionKey)
        end,
    }, DRAW_ACTION_REF)
    return ref
end

local function createGatedDrawActionRef(actionBuffer, actionKey, phaseGate)
    if type(actionBuffer.validateAction) == "function" then
        actionBuffer.validateAction("actions.get", actionKey)
    else
        validateActionKey("actions.get", actionKey)
    end
    return createDrawActionRef(actionBuffer, actionKey, phaseGate)
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

local function createBuffer(actionCatalog)
    local catalog = actionCatalog and createActionCatalog(actionCatalog.actions, actionCatalog.order) or nil
    local slots = {}
    local pending = {}
    local pendingEvents = {}
    local refs = {}
    local buffer = {}

    function buffer.stage(actionKey, value)
        validateDeclaredAction(catalog, "actions.stage", actionKey)
        if value == nil then
            slots[actionKey] = nil
            pending[actionKey] = nil
            return
        end
        slots[actionKey] = CloneValue(value)
        pending[actionKey] = true
    end

    function buffer.validateAction(context, actionKey)
        validateDeclaredAction(catalog, context, actionKey)
    end

    function buffer.read(actionKey)
        validateDeclaredAction(catalog, "actions.read", actionKey)
        return CloneValue(slots[actionKey])
    end

    function buffer.clear(actionKey)
        validateDeclaredAction(catalog, "actions.clear", actionKey)
        slots[actionKey] = nil
        pending[actionKey] = nil
    end

    function buffer.has(actionKey)
        validateDeclaredAction(catalog, "actions.has", actionKey)
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
        pending = {}
        pendingEvents = {}
    end

    function buffer.getRef(actionKey)
        validateDeclaredAction(catalog, "actions.get", actionKey)
        local ref = refs[actionKey]
        if ref ~= nil then
            return ref
        end
        ref = createDrawActionRef(buffer, actionKey)
        refs[actionKey] = ref
        return ref
    end

    function buffer.emitShared(id, eventName, payload)
        pendingEvents[#pendingEvents + 1] = {
            id = id,
            eventName = eventName,
            payload = CloneValue(payload),
        }
    end

    function buffer.executePendingActions(host, uiData, actionRuntime)
        if catalog ~= nil then
            for _, actionKey in ipairs(catalog.order) do
                if pending[actionKey] then
                    pending[actionKey] = nil
                    catalog.handlers[actionKey](host, uiData, actionRuntime, CloneValue(slots[actionKey]))
                end
            end
        end
    end

    function buffer.flushPendingSharedEvents(host)
        if #pendingEvents > 0 then
            local events = pendingEvents
            pendingEvents = {}
            for _, event in ipairs(events) do
                host.shared.emit(event.id, event.eventName, event.payload)
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
    createGatedDrawActionRef = createGatedDrawActionRef,
    isDrawActionRef = isDrawActionRef,
    createActionCatalog = createActionCatalog,
    validateDeclaredAction = validateDeclaredAction,
}
