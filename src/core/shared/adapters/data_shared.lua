local deps = ...

local logging = deps.logging
local data = deps.data

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
    local rawRef = data.createDeclaredRef(opts.declarations, opts.ownerId, name, opts.source)
    if rawRef.set then
        return wrapSetClearRef(rawRef)
    end
    return wrapReaderRef(rawRef)
end

--- Creates a lane's shared surface (`read/set/clear/emit`) over one owner's declarations.
--- `emit` is the lane's emit policy (immediate for runtime, staged for UI), owned by the caller.
---@param opts AdamantModpackLib.SharedRefsOpts
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
        emit = opts.emit,
    }
end

return dataShared
