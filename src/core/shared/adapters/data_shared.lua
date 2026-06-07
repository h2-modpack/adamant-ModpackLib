local deps = ...

local logging = deps.logging
local service = deps.service

local dataShared = {}

local function requireMethod(ref, methodName, name, source)
    local method = ref[methodName]
    if type(method) ~= "function" then
        logging.violate("shared.invalid_args", "%s: shared declaration '%s' does not support %s",
            source, tostring(name), methodName)
    end
    return method
end

local function wrapSetClearRef(rawRef)
    return {
        get = function()
            return rawRef:get()
        end,
        set = function(value)
            return rawRef:set(value)
        end,
        clear = function()
            return rawRef:clear()
        end,
    }
end

local function wrapReaderRef(rawRef)
    return {
        get = function()
            return rawRef:get()
        end,
    }
end

local function createSharedRef(opts, name)
    local rawRef = service.data.createDeclaredRef(opts.record, opts.host, name, opts.source)
    if rawRef.set then
        return wrapSetClearRef(rawRef)
    end
    return wrapReaderRef(rawRef)
end

local function emitShared(opts, id, eventName, payload)
    if opts.lane == "ui" then
        service.validateEmit(opts.source .. ".emit", id, eventName)
        return opts.actionBuffer.emitShared(id, eventName, payload)
    end
    return service.emitForModule(opts.host, id, eventName, payload)
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
        emit = function(id, eventName, payload)
            return emitShared(opts, id, eventName, payload)
        end,
    }
end

return dataShared
