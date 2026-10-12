local deps = ...

local logging = deps.logging
local currentRunCache = deps.currentRunCache

local dataCache = {}

-- `currentRun` is the only cache domain; `prepareDefinition` validates every declaration
-- (domain, key, factory), so only the author-supplied declaration name is checked here.
local function requireDeclaration(declarations, name, source)
    local declaration = declarations[name]
    if declaration == nil then
        logging.violate("cache.invalid_args", "%s: unknown cache declaration '%s'", source, tostring(name))
    end
    return declaration
end

---@param opts { declarations: table<string, table>, ownerId: string, source: string }
function dataCache.create(opts)
    local refs = {}
    local declarations = opts.declarations
    local source = opts.source

    local function ref(name)
        local cached = refs[name]
        if cached == nil then
            local declaration = requireDeclaration(declarations, name, source)
            cached = currentRunCache.create(opts.ownerId, declaration.key, declaration.factory)
            refs[name] = cached
        end
        return cached
    end

    return {
        currentRun = {
            get = function(name)
                return ref(name).get()
            end,
            clear = function(name)
                return ref(name).clear()
            end,
        },
    }
end

return dataCache
