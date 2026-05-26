local deps = ...

local logging = deps.logging
local phaseGate = deps.phaseGate
local service = deps.service

local dataCache = {}

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

local function wrapGetClearRef(rawRef)
    return {
        get = function()
            phaseGate.requireRuntime()
            return rawRef:get()
        end,
        clear = function()
            phaseGate.requireRuntime()
            return rawRef:clear()
        end,
    }
end

local function createCurrentRunRef(opts, declaration)
    return wrapGetClearRef(service.currentRun.create(opts.ownerId, declaration.key, {
        factory = declaration.factory,
    }))
end

local function createRef(opts, declaration)
    if declaration.domain == "currentRun" then
        return createCurrentRunRef(opts, declaration)
    end
    logging.violate("cache.invalid_args", "%s: invalid prepared cache domain", opts.source)
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

    return {
        currentRun = {
            get = function(name)
                return ref(name, "currentRun"):get()
            end,
            clear = function(name)
                local cacheRef = ref(name, "currentRun")
                return requireMethod(cacheRef, "clear", name, source)()
            end,
        },
    }
end

return dataCache
