local deps = ...
local logging = deps.logging
local modutil = deps.modutil
local REGISTRY_KEY = deps.registryKey

if not (modutil and modutil.mod and modutil.mod.Path) then
    logging.violate("hooks.modutil_unavailable", "hooks: SGG_Modding-ModUtil is not available")
end
local modutilPath = modutil.mod.Path

local function getRegistry(owner)
    if type(owner) ~= "table" then
        logging.violate("hooks.invalid_registration", "hooks: owner must be a persistent table")
    end

    local registry = owner[REGISTRY_KEY]
    if not registry then
        registry = {
            slots = {},
        }
        owner[REGISTRY_KEY] = registry
    end
    return registry
end

local function slotId(kind, path, key)
    return kind .. "\0" .. path .. "\0" .. key
end

local function getSlot(owner, kind, path, key)
    local registry = getRegistry(owner)
    local id = slotId(kind, path, key)
    local state = registry.slots[id]
    if not state then
        state = {
            kind = kind,
            path = path,
            key = key,
            registered = false,
        }
        registry.slots[id] = state
    end
    return state, registry
end

local function clearPendingState(state)
    state.pendingHandler = nil
    state.pendingReplacement = nil
    state.pendingContext = nil
end

local function applyWrapState(state)
    if state.pendingHandler ~= nil then
        state.handler = state.pendingHandler
    end

    if not state.registered then
        modutilPath.Wrap(state.path, function(base, ...)
            local current = state.handler
            if current then
                return current(base, ...)
            end
            return base(...)
        end)
        state.registered = true
    end
end

local function applyOverrideState(state)
    local replacement = state.pendingReplacement

    state.replacement = replacement

    if type(replacement) == "function" then
        if not state.registered then
            modutilPath.Override(state.path, function(...)
                local current = state.replacement
                if type(current) ~= "function" then
                    logging.violate("hooks.inactive_override", "hooks.override: function replacement is inactive")
                end
                return current(...)
            end)
            state.registered = true
            state.usesDispatcher = true
        elseif not state.usesDispatcher then
            modutilPath.Restore(state.path)
            modutilPath.Override(state.path, function(...)
                local current = state.replacement
                if type(current) ~= "function" then
                    logging.violate("hooks.inactive_override", "hooks.override: function replacement is inactive")
                end
                return current(...)
            end)
            state.usesDispatcher = true
        end
        return
    end

    if state.registered then
        modutilPath.Restore(state.path)
    end
    modutilPath.Override(state.path, replacement)
    state.registered = true
    state.usesDispatcher = false
end

local function applyContextWrapState(state)
    if state.pendingContext ~= nil then
        state.context = state.pendingContext
    end

    if not state.registered then
        modutilPath.Context.Wrap(state.path, function(...)
            local current = state.context
            if current then
                return current(...)
            end
        end)
        state.registered = true
    end
end

local function installWrap(owner, path, key, handler)
    local state = getSlot(owner, "wrap", path, key)
    state.pendingHandler = handler
    applyWrapState(state)
    clearPendingState(state)
    return state
end

local function installOverride(owner, path, key, replacement)
    local state = getSlot(owner, "override", path, key)
    state.pendingReplacement = replacement
    applyOverrideState(state)
    clearPendingState(state)
    return state
end

local function installContextWrap(owner, path, key, context)
    local state = getSlot(owner, "contextWrap", path, key)
    state.pendingContext = context
    applyContextWrapState(state)
    clearPendingState(state)
    return state
end

local function deactivateSlot(state)
    if state.kind == "wrap" then
        state.handler = nil
        return
    end

    if state.kind == "contextWrap" then
        state.context = nil
        return
    end

    if state.kind == "override" then
        state.replacement = nil
        if state.registered then
            modutilPath.Restore(state.path)
            state.registered = false
        end
    end
end

return {
    installWrap = installWrap,
    installOverride = installOverride,
    installContextWrap = installContextWrap,
    deactivateSlot = deactivateSlot,
}
