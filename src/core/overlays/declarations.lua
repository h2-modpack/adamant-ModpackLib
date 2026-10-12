local deps = ...

-- Contact point for authored overlay declarations: module declarations validate here when
-- declared, system defines validate here through the retained declaration surface, and replay
-- trusts the recorded entries.
local logging = deps.logging
local regions = deps.regions
local fonts = deps.fonts
local declarations = {}

local function readOnlyView(source, label)
    return setmetatable({}, {
        __index = source,
        __newindex = function()
            logging.violate("overlays.invalid_registration", "%s is read-only", label)
        end,
        __pairs = function()
            return pairs(source)
        end,
    })
end

local regionNames = {}
for name in pairs(regions) do
    regionNames[name] = true
end

declarations.regions = readOnlyView(regionNames, "overlays.regions")
declarations.fonts = readOnlyView(fonts, "overlays.fonts")

local function validateName(context, name)
    if type(name) ~= "string" or name == "" then
        logging.violate("overlays.invalid_registration", "%s: name must be a non-empty string", context)
    end
end

local function validatePath(context, path)
    if type(path) ~= "string" or path == "" then
        logging.violate("overlays.invalid_registration", "%s: path must be a non-empty string", context)
    end
end

local function validateSpec(context, spec)
    if type(spec) ~= "table" then
        logging.violate("overlays.invalid_registration", "%s: spec must be a table", context)
    end
    if spec.hudVisibility ~= nil and spec.hudVisibility ~= "follow" and spec.hudVisibility ~= "independent" then
        logging.violate("overlays.invalid_registration", "%s: hudVisibility must be follow or independent", context)
    end
    if spec.region ~= nil and regionNames[spec.region] == nil then
        logging.violate("overlays.invalid_registration", "%s: unknown region '%s'", context, tostring(spec.region))
    end
    if type(spec.columns) == "table" then
        for index, column in ipairs(spec.columns) do
            if type(column) ~= "table" then
                logging.violate("overlays.invalid_registration", "%s: column #%d must be a table", context, index)
            end
        end
    end
end

local function validateCallback(context, callback)
    if type(callback) ~= "function" then
        logging.violate("overlays.invalid_registration", "%s: callback must be a function", context)
    end
end

local function validateTableSpec(context, spec)
    validateSpec(context, spec)
    if type(spec.columns) ~= "table" or #spec.columns == 0 then
        logging.violate("overlays.invalid_registration", "%s: columns must be a non-empty array", context)
    end
    local maxRows = tonumber(spec.maxRows)
    if not maxRows or maxRows < 1 or math.floor(maxRows) ~= maxRows then
        logging.violate("overlays.invalid_registration", "%s: maxRows must be a positive integer", context)
    end
end

local function validateIntervalOpts(context, opts)
    if opts == nil then
        return
    end
    if type(opts) ~= "table" then
        logging.violate("overlays.invalid_registration", "%s: opts must be a table", context)
    end
    if opts.when ~= nil and type(opts.when) ~= "function" then
        logging.violate("overlays.invalid_registration", "%s: opts.when must be a function", context)
    end
end

--- Validates a line (or stamp) declaration for paths that do not record declarations.
function declarations.validateLine(context, name, spec)
    validateName(context, name)
    validateSpec(context, spec)
end

declarations.validateCallback = validateCallback

local function recordDeclaration(target, entry)
    target.entries[#target.entries + 1] = entry
end

function declarations.create()
    return {
        entries = {},
    }
end

function declarations.declareLine(target, context, name, spec)
    validateName(context, name)
    validateSpec(context, spec)
    recordDeclaration(target, {
        kind = "createLine",
        name = name,
        spec = spec,
    })
end

function declarations.declareTable(target, context, name, spec)
    validateName(context, name)
    validateTableSpec(context, spec)
    recordDeclaration(target, {
        kind = "createTable",
        name = name,
        spec = spec,
    })
end

function declarations.declareCommit(target, context, callback)
    validateCallback(context, callback)
    recordDeclaration(target, {
        kind = "onCommit",
        callback = callback,
    })
end

function declarations.declareInterval(target, context, name, seconds, callback, opts)
    validateName(context, name)
    validateCallback(context, callback)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then
        logging.violate("overlays.invalid_registration", "%s: seconds must be positive", context)
    end
    validateIntervalOpts(context, opts)
    recordDeclaration(target, {
        kind = "onInterval",
        name = name,
        seconds = seconds,
        callback = callback,
        opts = opts,
    })
end

function declarations.declareAfterHook(target, context, path, callback)
    validatePath(context, path)
    validateCallback(context, callback)
    recordDeclaration(target, {
        kind = "afterHook",
        path = path,
        callback = callback,
    })
end

function declarations.replay(target, registrar)
    for _, entry in ipairs(target and target.entries or {}) do
        if entry.kind == "createLine" then
            registrar.createLine(entry.name, entry.spec)
        elseif entry.kind == "createTable" then
            registrar.createTable(entry.name, entry.spec)
        elseif entry.kind == "onCommit" then
            registrar.onCommit(entry.callback)
        elseif entry.kind == "onInterval" then
            registrar.onInterval(entry.name, entry.seconds, entry.callback, entry.opts)
        elseif entry.kind == "afterHook" then
            registrar.afterHook(entry.path, entry.callback)
        end
    end
end

return declarations
