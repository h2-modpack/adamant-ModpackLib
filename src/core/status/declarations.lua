local deps = ...

local logging = deps.logging
local values = deps.values

local declarations = {}

local StableIdentifierPattern = "^[A-Za-z][A-Za-z0-9_]*$"
local StableIdentifierDescription = "must start with a letter and contain only letters, digits, and underscores"

local RootForbiddenFields = {
    alias = true,
    hash = true,
    mode = true,
}

local function isStableIdentifier(value)
    return type(value) == "string" and string.match(value, StableIdentifierPattern) ~= nil
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function validateStatusDeclaration(alias, declaration)
    if not isStableIdentifier(alias) then
        logging.violate("status.invalid_alias", "module.status.define: status alias '%s' %s",
            tostring(alias), StableIdentifierDescription)
    end
    if type(declaration) ~= "table" then
        logging.violate("status.invalid_declaration", "module.status.define: status '%s' must be a table",
            tostring(alias))
    end
    for field in pairs(RootForbiddenFields) do
        if declaration[field] ~= nil then
            logging.violate("status.invalid_field", "module.status.define: status '%s' must not declare '%s'",
                tostring(alias), field)
        end
    end
    if declaration.persist == nil then
        logging.violate("status.missing_persist", "module.status.define: status '%s' must declare persist",
            tostring(alias))
    elseif type(declaration.persist) ~= "boolean" then
        logging.violate("status.invalid_persist", "module.status.define: status '%s' persist must be boolean",
            tostring(alias))
    end
end

function declarations.compileStorage(statusDeclarations)
    if statusDeclarations == nil then
        return {}
    end
    if type(statusDeclarations) ~= "table" then
        logging.violate("status.invalid_declaration_set", "module.status.define expects a table")
    end

    local storage = {}
    for _, alias in ipairs(sortedKeys(statusDeclarations)) do
        local declaration = statusDeclarations[alias]
        validateStatusDeclaration(alias, declaration)

        local node = values.deepCopy(declaration)
        node.alias = alias
        node.mode = "runtime"
        node.hash = false
        storage[#storage + 1] = node
    end
    return storage
end

return declarations
