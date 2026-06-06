local deps = ...

local logging = deps.logging
local values = deps.values
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

local function ensureDataDeclarations(record)
    if not record.sharedDataDeclarations then
        record.sharedDataDeclarations = sharedData.createDeclarations()
    end
    return record.sharedDataDeclarations
end

local function makeNoopReceipt()
    return {
        commit = function()
            return true, nil
        end,
        dispose = function()
            return true, nil
        end,
    }
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

local function stageDataDeclaration(context, access, declarations, hostProvider, name, opts)
    validateName(context, name)
    if opts ~= nil and type(opts) ~= "table" then
        logging.violate("shared.invalid_args", "%s opts must be a table when provided", context)
    end
    opts = opts or {}
    validateId(context, opts.id)

    if declarations.byName[name] then
        logging.violate("shared.invalid_args", "%s name '%s' is already declared by this host", context, name)
    end

    if access == "owner" then
        if declarations.ownerIds[opts.id] then
            logging.violate("shared.invalid_args", "%s id '%s' is already owned by this host", context, opts.id)
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
            local host = hostProvider and hostProvider() or nil
            return host ~= nil and host.isEnabled() == true
        end,
    }
    declarations.byName[name] = declaration
    declarations.entries[#declarations.entries + 1] = declaration
    if access == "owner" then
        declarations.ownerIds[opts.id] = true
    end
    return true
end

function sharedData.stageOwnerDeclaration(declarations, hostProvider, name, opts)
    return stageDataDeclaration("module.shared.data.owner", "owner", declarations, hostProvider, name, opts)
end

function sharedData.stageReaderDeclaration(declarations, hostProvider, name, opts)
    return stageDataDeclaration("module.shared.data.reader", "reader", declarations, hostProvider, name, opts)
end

function sharedData.stageOwner(record, host, name, opts)
    return sharedData.stageOwnerDeclaration(ensureDataDeclarations(record), function()
        return host
    end, name, opts)
end

function sharedData.stageReader(record, host, name, opts)
    return sharedData.stageReaderDeclaration(ensureDataDeclarations(record), function()
        return host
    end, name, opts)
end

function sharedData.install(ownerId, declarations)
    validateOwnerId("shared.data.install", ownerId)
    if not hasOwnerDeclarations(declarations) then
        return makeNoopReceipt()
    end

    local install = {
        ownerId = ownerId,
        ownerToken = {},
        entries = {},
        previous = {},
        committed = false,
        disposed = false,
    }

    for _, entry in ipairs(declarations.entries) do
        if entry.access == "owner" then
            install.entries[#install.entries + 1] = entry
        end
    end

    return {
        commit = function()
            if install.disposed or install.committed then
                return true, nil
            end

            for _, entry in ipairs(install.entries) do
                local previous = records[entry.id]
                if previous and previous.ownerId ~= ownerId then
                    logging.violate(
                        "shared.duplicate_publisher",
                        "shared.data '%s' is already published by '%s'",
                        tostring(entry.id),
                        tostring(previous.ownerId))
                end
                install.previous[entry.id] = previous
                records[entry.id] = {
                    id = entry.id,
                    ownerId = ownerId,
                    ownerToken = install.ownerToken,
                    default = copyOptional(entry.default),
                    defaultView = protectOptional(entry.default),
                    hasDefault = entry.hasDefault == true,
                    value = nil,
                    valueView = nil,
                    hasValue = false,
                    isEnabled = entry.isEnabled,
                }
            end

            install.committed = true
            declarations.ownerToken = install.ownerToken
            return true, nil
        end,
        dispose = function()
            if install.disposed then
                return true, nil
            end
            if install.committed then
                for index = #install.entries, 1, -1 do
                    local entry = install.entries[index]
                    local current = records[entry.id]
                    if current
                        and current.ownerId == ownerId
                        and current.ownerToken == install.ownerToken
                    then
                        records[entry.id] = install.previous[entry.id]
                    end
                end
                if declarations.ownerToken == install.ownerToken then
                    declarations.ownerToken = nil
                end
            end
            install.disposed = true
            return true, nil
        end,
    }
end

local function requireOwnerRecord(context, ownerId, ownerToken, id)
    validateOwnerId(context, ownerId)
    validateId(context, id)

    local record = records[id]
    if not record or record.ownerId ~= ownerId or record.ownerToken ~= ownerToken then
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

local function requireDataDeclaration(record, name, source)
    local declarations = record and record.sharedDataDeclarations or nil
    local declaration = declarations and declarations.byName and declarations.byName[name] or nil
    if not declaration then
        logging.violate("shared.invalid_args", "%s: unknown shared declaration '%s'", source, tostring(name))
    end
    return declarations, declaration
end

local function createOwnerRef(context, declarations, declaration, host)
    local snapshotValue = copyOptional(declaration.default)
    local snapshot = protectOptional(snapshotValue)
    local id = declaration.id
    local ref = {}
    ref.get = function()
        local ownerRecord = records[id]
        if ownerRecord and ownerRecord.ownerId == host.getOwnerId()
            and ownerRecord.ownerToken == declarations.ownerToken
        then
            return readView(id, snapshot)
        end
        return snapshot
    end
    ref.set = function(_, value)
        validateValue(context .. ".set", value)
        local ownerRecord = requireOwnerRecord(context .. ".set", host.getOwnerId(), declarations.ownerToken, id)
        ownerRecord.value = values.deepCopy(value)
        ownerRecord.valueView = protectOptional(ownerRecord.value)
        ownerRecord.hasValue = true
        snapshot = ownerRecord.valueView
        return true
    end
    ref.clear = function()
        local ownerRecord = requireOwnerRecord(context .. ".clear", host.getOwnerId(), declarations.ownerToken, id)
        ownerRecord.value = nil
        ownerRecord.valueView = nil
        ownerRecord.hasValue = false
        snapshot = ownerRecord.defaultView or protectOptional(snapshotValue)
        return true
    end
    return ref
end

function sharedData.createDeclaredRef(record, host, name, source)
    local declarations, declaration = requireDataDeclaration(record, name, source)
    if declaration.access == "owner" then
        return createOwnerRef("shared.data.declared", declarations, declaration, host)
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
