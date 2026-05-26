local deps = ...

local logging = deps.logging
local phaseGate = deps.phaseGate
local service = deps.service

local dataCache = {}

local function requirePhase(phase)
    if phase == "draw" then
        phaseGate.requireAnyDraw()
    else
        phaseGate.requireRuntime()
    end
end

local function requireDeclaration(declarations, name, source)
    local declaration = declarations and declarations[name] or nil
    if declaration == nil then
        logging.violate("cache.invalid_args", "%s: unknown cache declaration '%s'", source, tostring(name))
    end
    return declaration
end

local function requireDomain(declaration, domain, name, source)
    if declaration.domain ~= domain then
        logging.violate("cache.invalid_args", "%s: cache declaration '%s' is %s, not %s",
            source, tostring(name), tostring(declaration.domain), domain)
    end
end

local function requireMethod(ref, methodName, name, source)
    local method = ref[methodName]
    if type(method) ~= "function" then
        logging.violate("cache.invalid_args", "%s: cache declaration '%s' does not support %s",
            source, tostring(name), methodName)
    end
    return method
end

local function wrapReadOnlyGet(phase, load)
    return {
        get = function()
            requirePhase(phase)
            return load()
        end,
    }
end

local function wrapSetClearRef(phase, rawRef)
    local ref
    ref = {
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
    return ref
end

local function wrapGetClearRef(phase, rawRef)
    return {
        get = function()
            requirePhase(phase)
            return rawRef:get()
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

local function createPersistentRef(opts, declaration)
    if opts.phase == "draw" then
        return wrapReadOnlyGet("draw", function()
            return service.persistent.read(opts.cacheStore, opts.ownerId, declaration.key, declaration.default)
        end)
    end

    return wrapSetClearRef("runtime", service.persistent.create(opts.cacheStore, opts.ownerId, declaration.key, {
        default = declaration.default,
    }))
end

local function createCurrentRunRef(opts, declaration)
    if opts.phase == "draw" then
        logging.violate("cache.invalid_args", "%s: currentRun cache is not available during draw", opts.source)
    end

    return wrapGetClearRef("runtime", service.currentRun.create(opts.ownerId, declaration.key, {
        factory = declaration.factory,
    }))
end

local function createSharedRef(opts, declaration)
    if declaration.access == "owner" then
        return wrapSetClearRef(
            opts.phase,
            service.shared.createDeclaredOwner(opts.record, opts.host, declaration.id, {
                default = declaration.default,
            })
        )
    end

    return wrapReaderRef(opts.phase, service.shared.createReader(declaration.id, {
        access = "reader",
        fallback = declaration.fallback,
    }))
end

local function createRef(opts, declaration)
    if declaration.domain == "persistent" then
        return createPersistentRef(opts, declaration)
    end
    if declaration.domain == "currentRun" then
        return createCurrentRunRef(opts, declaration)
    end
    if declaration.domain == "shared" then
        return createSharedRef(opts, declaration)
    end
    logging.violate("cache.invalid_args", "%s: invalid prepared cache domain", opts.source)
end

function dataCache.stageSharedOwnerPublications(record, host, definitions)
    local declarations = definitions and definitions.cache or {}
    for _, name in ipairs(definitions and definitions._cacheOrder or {}) do
        local declaration = declarations[name]
        if declaration and declaration.domain == "shared" and declaration.access == "owner" then
            service.shared.stagePublication(record, host, declaration.id, {
                default = declaration.default,
            })
        end
    end
end

function dataCache.create(opts)
    local refs = {}
    local declarations = opts.definition and opts.definition.cache or {}
    local source = opts.source

    local function ref(name, domain)
        local cached = refs[name]
        if cached ~= nil then
            if domain ~= nil then
                requireDomain(requireDeclaration(declarations, name, source), domain, name, source)
            end
            return cached
        end

        local declaration = requireDeclaration(declarations, name, source)
        if domain ~= nil then
            requireDomain(declaration, domain, name, source)
        end
        cached = createRef(opts, declaration)
        refs[name] = cached
        return cached
    end

    local persistent = {
        read = function(name)
            return ref(name, "persistent"):get()
        end,
    }

    local currentRun
    local shared = {
        read = function(name)
            return ref(name, "shared"):get()
        end,
        set = function(name, value)
            local cacheRef = ref(name, "shared")
            return requireMethod(cacheRef, "set", name, source)(value)
        end,
        clear = function(name)
            local cacheRef = ref(name, "shared")
            return requireMethod(cacheRef, "clear", name, source)()
        end,
    }

    if opts.phase ~= "draw" then
        persistent.set = function(name, value)
            local cacheRef = ref(name, "persistent")
            return requireMethod(cacheRef, "set", name, source)(value)
        end
        persistent.clear = function(name)
            local cacheRef = ref(name, "persistent")
            return requireMethod(cacheRef, "clear", name, source)()
        end
        currentRun = {
            get = function(name)
                return ref(name, "currentRun"):get()
            end,
            clear = function(name)
                local cacheRef = ref(name, "currentRun")
                return requireMethod(cacheRef, "clear", name, source)()
            end,
        }
    end

    return {
        persistent = persistent,
        currentRun = currentRun,
        shared = shared,
    }
end

return dataCache
