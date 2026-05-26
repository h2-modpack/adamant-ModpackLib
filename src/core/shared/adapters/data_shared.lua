local deps = ...

local logging = deps.logging
local phaseGate = deps.phaseGate
local service = deps.service

local dataShared = {}

local function requirePhase(phase)
    if phase == "draw" then
        phaseGate.requireAnyDraw()
    else
        phaseGate.requireRuntime()
    end
end

local function requireMethod(ref, methodName, name, source)
    local method = ref[methodName]
    if type(method) ~= "function" then
        logging.violate("shared.invalid_args", "%s: shared declaration '%s' does not support %s",
            source, tostring(name), methodName)
    end
    return method
end

local function wrapSetClearRef(phase, rawRef)
    return {
        get = function()
            requirePhase(phase)
            return rawRef:get()
        end,
        set = function(value)
            requirePhase(phase)
            return rawRef:set(value)
        end,
        clear = function()
            requirePhase(phase)
            return rawRef:clear()
        end,
    }
end

local function wrapReaderRef(phase, rawRef)
    return {
        get = function()
            requirePhase(phase)
            return rawRef:get()
        end,
    }
end

local function createSharedRef(opts, name)
    local rawRef = service.data.createDeclaredRef(opts.record, opts.host, name, opts.source)
    if rawRef.set then
        return wrapSetClearRef(opts.phase, rawRef)
    end
    return wrapReaderRef(opts.phase, rawRef)
end

function dataShared.create(opts)
    local refs = {}
    local source = opts.source

    local function ref(name)
        local cached = refs[name]
        if cached ~= nil then
            return cached
        end

        cached = createSharedRef(opts, name)
        refs[name] = cached
        return cached
    end

    return {
        read = function(name)
            return ref(name):get()
        end,
        set = function(name, value)
            local sharedRef = ref(name)
            return requireMethod(sharedRef, "set", name, source)(value)
        end,
        clear = function(name)
            local sharedRef = ref(name)
            return requireMethod(sharedRef, "clear", name, source)()
        end,
    }
end

return dataShared
