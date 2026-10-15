-- Hotkey request declarations: the `module.hotkeys.request(...)` contact point and the compile step
-- that turns requests into Lib-declared binding storage.

local deps = ...

local logging = deps.logging
local identifiers = deps.identifiers
local bindings = deps.bindings

local declarations = {}

local KnownRequestFields = {
    label = true,
    default = true,
    alias = true,
    tooltip = true,
    onPress = true,
}

---@class AdamantModpackLib.HotkeyRequest
---@field id string
---@field label string
---@field default string
---@field alias string Binding storage alias.
---@field tooltip string?
---@field onPress fun(host: AdamantModpackLib.Host, runtime: AdamantModpackLib.RuntimeContext)
---@field order integer Declaration order within the module.

---@return { requests: AdamantModpackLib.HotkeyRequest[], byId: table<string, AdamantModpackLib.HotkeyRequest>,
---    byAlias: table<string, AdamantModpackLib.HotkeyRequest> }
function declarations.create()
    return {
        requests = {},
        byId = {},
        byAlias = {},
    }
end

local function invalid(id, fmt, ...)
    logging.violate("hotkeys.invalid_declaration", "module.hotkeys.request '%s': " .. fmt, tostring(id), ...)
end

---Validates and records one request. Raises through `logging.violate` on invalid input.
---@param bucket table Bucket from `declarations.create()`.
---@param id string
---@param opts table
function declarations.request(bucket, id, opts)
    if not identifiers.isStable(id) then
        logging.violate("hotkeys.invalid_declaration", "module.hotkeys.request: id '%s' %s",
            tostring(id), identifiers.STABLE_DESCRIPTION)
    end
    if type(opts) ~= "table" then
        invalid(id, "opts must be a table")
    end
    for field in pairs(opts) do
        if not KnownRequestFields[field] then
            invalid(id, "unknown field '%s'", tostring(field))
        end
    end
    if type(opts.label) ~= "string" or opts.label == "" then
        invalid(id, "label must be a non-empty string")
    end
    if type(opts.onPress) ~= "function" then
        invalid(id, "onPress must be a function")
    end
    if opts.tooltip ~= nil and type(opts.tooltip) ~= "string" then
        invalid(id, "tooltip must be a string when provided")
    end
    local default = opts.default
    if default == nil then
        default = bindings.UNBOUND
    end
    if not bindings.isValid(default) then
        invalid(id, "default '%s' is not a valid binding; use \"\" or [Ctrl+][Shift+][Alt+]F1-F12",
            tostring(default))
    end
    local alias = opts.alias
    if alias == nil then
        alias = "Hotkey_" .. id
    elseif not identifiers.isStable(alias) then
        invalid(id, "alias '%s' %s", tostring(alias), identifiers.STABLE_DESCRIPTION)
    end

    if bucket.byId[id] ~= nil then
        logging.violate("hotkeys.duplicate_request", "module.hotkeys.request: hotkey '%s' already requested", id)
    end
    if bucket.byAlias[alias] ~= nil then
        logging.violate("hotkeys.duplicate_request",
            "module.hotkeys.request '%s': alias '%s' is already used by hotkey '%s'",
            id, alias, bucket.byAlias[alias].id)
    end

    local request = {
        id = id,
        label = opts.label,
        default = default,
        alias = alias,
        tooltip = opts.tooltip,
        onPress = opts.onPress,
        order = #bucket.requests + 1,
    }
    bucket.requests[#bucket.requests + 1] = request
    bucket.byId[id] = request
    bucket.byAlias[alias] = request
end

local function collectDeclaredAliases(storage, into)
    if type(storage) ~= "table" then
        return into
    end
    for _, node in ipairs(storage) do
        if type(node) == "table" then
            if type(node.alias) == "string" then
                into[node.alias] = true
            end
            if type(node.bits) == "table" then
                for _, bit in ipairs(node.bits) do
                    if type(bit) == "table" and type(bit.alias) == "string" then
                        into[bit.alias] = true
                    end
                end
            end
        end
    end
    return into
end

---Compiles requests into binding storage roots: one persisted `string` root per request,
---`hash = false`, defaulting to the request default. The module's own `module.data.define` and
---status storage must not declare a binding alias.
---@param bucket table Bucket from `declarations.create()`.
---@param moduleStorage table? Storage the module declared through `module.data.define`.
---@param statusStorage table? Compiled status storage.
---@return { storage: table[], requests: AdamantModpackLib.HotkeyRequest[] }
function declarations.compile(bucket, moduleStorage, statusStorage)
    local declared = collectDeclaredAliases(moduleStorage, {})
    collectDeclaredAliases(statusStorage, declared)

    local storage = {}
    for index, request in ipairs(bucket.requests) do
        if declared[request.alias] then
            logging.violate("hotkeys.alias_collision",
                "hotkey '%s' binding alias '%s' is declared by Lib; remove it from module.data.define",
                request.id, request.alias)
        end
        storage[index] = {
            alias = request.alias,
            type = "string",
            default = request.default,
            hash = false,
        }
    end
    return {
        storage = storage,
        requests = bucket.requests,
    }
end

return declarations
