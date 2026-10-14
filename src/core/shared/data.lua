local deps = ...

local logging = deps.logging
local values = deps.values
local receipt = deps.receipt
local sharedRegistry = deps.sharedRegistry

sharedRegistry.records = sharedRegistry.records or {}

local records = sharedRegistry.records
local sharedData = {}

local function validateId(context, id)
    if type(id) ~= "string" or id == "" then
        logging.violate("shared.invalid_args", "%s id must be a non-empty string", context)
    end
end

local function validateName(context, name)
    if type(name) ~= "string" or name == "" then
        logging.violate("shared.invalid_args", "%s name must be a non-empty string", context)
    end
end

local function validateOwnerId(context, ownerId)
    if type(ownerId) ~= "string" or ownerId == "" then
        logging.violate("shared.invalid_args", "%s ownerId must be a non-empty string", context)
    end
end

local function validateTableKey(context, key)
    local keyType = type(key)
    if keyType ~= "number" and keyType ~= "string" then
        logging.violate("shared.invalid_value", "%s table keys must be strings or numbers", context)
    end
end

local function validateValue(context, value, seen)
    if value == nil then
        logging.violate("shared.invalid_value", "%s value must not be nil; use clear instead", context)
    end

    local valueType = type(value)
    if valueType == "boolean" or valueType == "number" or valueType == "string" then
        return
    end
    if valueType ~= "table" then
        logging.violate("shared.invalid_value", "%s value must be a scalar or table", context)
    end

    seen = seen or {}
    if seen[value] then
        return
    end
    seen[value] = true

    for key, child in pairs(value) do
        validateTableKey(context, key)
        validateValue(context, child, seen)
    end
end

local function validateOptionalValue(context, value)
    if value ~= nil then
        validateValue(context, value)
    end
end

local function copyOptional(value)
    if value == nil then
        return nil
    end
    return values.deepCopy(value)
end

local function buildReadOnlyView(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local view = {}
    local proxy = {}
    seen[value] = proxy

    for key, child in pairs(value) do
        view[key] = buildReadOnlyView(child, seen)
    end

    setmetatable(proxy, {
        __index = view,
        __newindex = function()
            logging.violate("shared.invalid_value", "shared data table views are read-only")
        end,
        __pairs = function()
            return pairs(view)
        end,
        __ipairs = function()
            return ipairs(view)
        end,
        __len = function()
            return #view
        end,
        __metatable = false,
    })

    return proxy
end

local function protectOptional(value)
    if value == nil then
        return nil
    end
    return buildReadOnlyView(value)
end

local function hasOwnerDeclarations(declarations)
    if not declarations then
        return false
    end
    for _, declaration in ipairs(declarations.entries or {}) do
        if declaration.access == "owner" then
            return true
        end
    end
    return false
end

function sharedData.createDeclarations()
    return {
        entries = {},
        byName = {},
        ownerIds = {},
    }
end

local function stageDataDeclaration(context, access, declarations, getModule, name, opts)
    validateName(context, name)
    if opts ~= nil and type(opts) ~= "table" then
        logging.violate("shared.invalid_args", "%s opts must be a table when provided", context)
    end
    opts = opts or {}
    validateId(context, opts.id)

    if declarations.byName[name] then
        logging.violate("shared.invalid_args", "%s name '%s' is already declared by this module", context, name)
    end

    if access == "owner" then
        if declarations.ownerIds[opts.id] then
            logging.violate("shared.invalid_args", "%s id '%s' is already owned by this module", context, opts.id)
        end
        if opts.fallback ~= nil then
            logging.violate("shared.invalid_args", "%s fallback is only valid for reader declarations", context)
        end
        validateOptionalValue(context .. " default", opts.default)
    else
        if opts.default ~= nil then
            logging.violate("shared.invalid_args", "%s default is only valid for owner declarations", context)
        end
        validateOptionalValue(context .. " fallback", opts.fallback)
    end

    local declaration = {
        name = name,
        id = opts.id,
        access = access,
        default = copyOptional(opts.default),
        fallback = copyOptional(opts.fallback),
        hasDefault = opts.default ~= nil,
        hasFallback = opts.fallback ~= nil,
        isEnabled = function()
            local module = getModule and getModule() or nil
            return module ~= nil and module.isEnabled() == true
        end,
    }
    declarations.byName[name] = declaration
    declarations.entries[#declarations.entries + 1] = declaration
    if access == "owner" then
        declarations.ownerIds[opts.id] = true
    end
    return true
end

function sharedData.stageOwnerDeclaration(declarations, getModule, name, opts)
    return stageDataDeclaration("module.shared.data.owner", "owner", declarations, getModule, name, opts)
end

function sharedData.stageReaderDeclaration(declarations, getModule, name, opts)
    return stageDataDeclaration("module.shared.data.reader", "reader", declarations, getModule, name, opts)
end

-- The receipt-private `ownerToken` scopes rollback/retire to the records this install wrote.
-- Each published record also carries its `declaration`, so refs created from the same
-- declarations recognize their own generation's record without a token side channel.
function sharedData.install(ownerId, declarations)
    validateOwnerId("shared.data.install", ownerId)
    if not hasOwnerDeclarations(declarations) then
        return receipt.noop("shared.data", receipt.PHASE_EFFECTS)
    end

    local ownerToken = {}
    local entries = {}
    local previous = {}

    for _, entry in ipairs(declarations.entries) do
        if entry.access == "owner" then
            entries[#entries + 1] = entry
        end
    end

    -- Clears every record this install still owns, replacing each with what
    -- `replacementFor(id)` returns.
    local function release(replacementFor)
        for index = #entries, 1, -1 do
            local id = entries[index].id
            local current = records[id]
            if current
                and current.ownerId == ownerId
                and current.ownerToken == ownerToken
            then
                records[id] = replacementFor(id)
            end
        end
        return true, nil
    end

    return receipt.create({
        name = "shared.data",
        phase = receipt.PHASE_EFFECTS,
        commit = function()
            for _, entry in ipairs(entries) do
                local existing = records[entry.id]
                if existing and existing.ownerId ~= ownerId then
                    logging.violate(
                        "shared.duplicate_publisher",
                        "shared.data '%s' is already published by '%s'",
                        tostring(entry.id),
                        tostring(existing.ownerId))
                end
                previous[entry.id] = existing
            end

            for _, entry in ipairs(entries) do
                records[entry.id] = {
                    id = entry.id,
                    ownerId = ownerId,
                    ownerToken = ownerToken,
                    declaration = entry,
                    default = copyOptional(entry.default),
                    defaultView = protectOptional(entry.default),
                    hasDefault = entry.hasDefault == true,
                    value = nil,
                    valueView = nil,
                    hasValue = false,
                    isEnabled = entry.isEnabled,
                }
            end

            return true, nil
        end,
        rollback = function()
            return release(function(id)
                return previous[id]
            end)
        end,
        -- Retire never restores the record it replaced, which belongs to a retired generation.
        retire = function()
            return release(function()
                return nil
            end)
        end,
    })
end

local function isOwnRecord(record, ownerId, declaration)
    return record ~= nil and record.ownerId == ownerId and record.declaration == declaration
end

local function requireOwnerRecord(context, ownerId, declaration)
    local id = declaration.id
    local record = records[id]
    if not isOwnRecord(record, ownerId, declaration) then
        logging.violate("shared.not_owner", "%s '%s' requires the active publishing owner", context, id)
    end
    return record
end

local function readView(id, fallbackView)
    validateId("shared.data.read", id)
    local record = records[id]
    if not record or not (record.isEnabled and record.isEnabled()) then
        return fallbackView
    end
    if record.hasValue then
        return record.valueView
    end
    if record.hasDefault then
        return record.defaultView
    end
    return fallbackView
end

local function requireDataDeclaration(declarations, name, source)
    local declaration = declarations.byName[name]
    if not declaration then
        logging.violate("shared.invalid_args", "%s: unknown shared declaration '%s'", source, tostring(name))
    end
    return declaration
end

local function createOwnerRef(context, ownerId, declaration)
    local snapshotValue = copyOptional(declaration.default)
    local snapshot = protectOptional(snapshotValue)
    local id = declaration.id
    local ref = {}
    ref.get = function()
        if isOwnRecord(records[id], ownerId, declaration) then
            return readView(id, snapshot)
        end
        return snapshot
    end
    ref.set = function(_, value)
        validateValue(context .. ".set", value)
        local ownerRecord = requireOwnerRecord(context .. ".set", ownerId, declaration)
        ownerRecord.value = values.deepCopy(value)
        ownerRecord.valueView = protectOptional(ownerRecord.value)
        ownerRecord.hasValue = true
        snapshot = ownerRecord.valueView
        return true
    end
    ref.clear = function()
        local ownerRecord = requireOwnerRecord(context .. ".clear", ownerId, declaration)
        ownerRecord.value = nil
        ownerRecord.valueView = nil
        ownerRecord.hasValue = false
        snapshot = ownerRecord.defaultView or protectOptional(snapshotValue)
        return true
    end
    return ref
end

---@param declarations table Module shared data declarations.
---@param ownerId string
---@param name string Author-supplied declaration name.
---@param source string
function sharedData.createDeclaredRef(declarations, ownerId, name, source)
    local declaration = requireDataDeclaration(declarations, name, source)
    if declaration.access == "owner" then
        return createOwnerRef("shared.data.declared", ownerId, declaration)
    end

    local fallbackValue = copyOptional(declaration.fallback)
    local fallbackView = protectOptional(fallbackValue)

    return {
        get = function()
            return readView(declaration.id, fallbackView)
        end,
    }
end

return sharedData
