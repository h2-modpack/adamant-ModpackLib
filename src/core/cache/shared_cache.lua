local deps = ...

local logging = deps.logging
local values = deps.values
local sharedRegistry = deps.sharedRegistry

sharedRegistry.records = sharedRegistry.records or {}

local records = sharedRegistry.records
local sharedCache = {}

local function validateId(context, id)
    if type(id) ~= "string" or id == "" then
        logging.violate("cache.invalid_args", "%s id must be a non-empty string", context)
    end
end

local function validateOwnerId(context, ownerId)
    if type(ownerId) ~= "string" or ownerId == "" then
        logging.violate("cache.invalid_args", "%s ownerId must be a non-empty string", context)
    end
end

local function validateValue(context, value, seen)
    if value == nil then
        logging.violate("cache.invalid_value", "%s value must not be nil; use clear instead", context)
    end

    local valueType = type(value)
    if valueType == "boolean" or valueType == "number" or valueType == "string" then
        return
    end
    if valueType ~= "table" then
        logging.violate("cache.invalid_value", "%s value must be a scalar or table", context)
    end

    seen = seen or {}
    if seen[value] then
        return
    end
    seen[value] = true

    for key, child in pairs(value) do
        validateValue(context .. " key", key, seen)
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
        view[buildReadOnlyView(key, seen)] = buildReadOnlyView(child, seen)
    end

    setmetatable(proxy, {
        __index = view,
        __newindex = function()
            logging.violate("cache.invalid_value", "shared cache table views are read-only")
        end,
        __pairs = function()
            return pairs(view)
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

local function ensurePublicationSet(record)
    if not record.sharedCachePublications then
        record.sharedCachePublications = {
            entries = {},
            byId = {},
        }
    end
    return record.sharedCachePublications
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

local function hasPublicationEntries(publications)
    return publications and #(publications.entries or {}) > 0
end

local function stagePublication(context, record, host, id, opts)
    validateId(context, id)
    if opts ~= nil and type(opts) ~= "table" then
        logging.violate("cache.invalid_args", "%s opts must be a table when provided", context)
    end
    opts = opts or {}
    validateOptionalValue(context .. " default", opts.default)

    local publications = ensurePublicationSet(record)
    if publications.byId[id] then
        logging.violate("cache.invalid_args", "%s id '%s' is already published by this host", context, id)
    end

    local entry = {
        id = id,
        default = copyOptional(opts.default),
        hasDefault = opts.default ~= nil,
        isEnabled = function()
            return host.isEnabled()
        end,
    }
    publications.byId[id] = entry
    publications.entries[#publications.entries + 1] = entry
    return true
end

function sharedCache.stagePublication(record, host, id, opts)
    return stagePublication("cache.shared.declared", record, host, id, opts)
end

function sharedCache.install(ownerId, publications)
    validateOwnerId("cache.shared.install", ownerId)
    if not hasPublicationEntries(publications) then
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

    for _, entry in ipairs(publications.entries) do
        install.entries[#install.entries + 1] = entry
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
                        "cache.shared_duplicate_publisher",
                        "cache.shared '%s' is already published by '%s'",
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
            publications.ownerToken = install.ownerToken
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
                if publications.ownerToken == install.ownerToken then
                    publications.ownerToken = nil
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
        logging.violate("cache.shared_not_owner", "%s '%s' requires the active publishing owner", context, id)
    end
    return record
end

local function readView(id, fallbackView)
    validateId("cache.shared.read", id)
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

local function createOwnerRef(context, record, host, id, defaultValue)
    local publications = ensurePublicationSet(record)
    if not publications.byId[id] then
        logging.violate("cache.invalid_args", "%s requires a declared owner publication", context)
    end

    local snapshotValue = copyOptional(defaultValue)
    local snapshot = protectOptional(snapshotValue)
    local ref = {}
    ref.get = function()
        local ownerRecord = records[id]
        if ownerRecord and ownerRecord.ownerId == host.getHostId()
            and ownerRecord.ownerToken == publications.ownerToken
        then
            return readView(id, snapshot)
        end
        return snapshot
    end
    ref.set = function(_, value)
        validateValue(context .. ".set", value)
        local ownerRecord = requireOwnerRecord(context .. ".set", host.getHostId(), publications.ownerToken, id)
        ownerRecord.value = values.deepCopy(value)
        ownerRecord.valueView = protectOptional(ownerRecord.value)
        ownerRecord.hasValue = true
        snapshot = ownerRecord.valueView
        return true
    end
    ref.clear = function()
        local ownerRecord = requireOwnerRecord(context .. ".clear", host.getHostId(), publications.ownerToken, id)
        ownerRecord.value = nil
        ownerRecord.valueView = nil
        ownerRecord.hasValue = false
        snapshot = ownerRecord.defaultView or protectOptional(snapshotValue)
        return true
    end
    return ref
end

function sharedCache.createDeclaredOwner(record, host, id, opts)
    local context = "cache.shared.declared"
    validateId(context, id)
    if opts ~= nil and type(opts) ~= "table" then
        logging.violate("cache.invalid_args", "%s opts must be a table when provided", context)
    end
    opts = opts or {}
    validateOptionalValue(context .. " default", opts.default)
    return createOwnerRef(context, record, host, id, opts.default)
end

function sharedCache.createReader(id, opts)
    local context = "cache.shared.declared"
    validateId(context, id)
    if opts ~= nil and type(opts) ~= "table" then
        logging.violate("cache.invalid_args", "%s opts must be a table when provided", context)
    end
    opts = opts or {}
    if opts.access ~= nil and opts.access ~= "reader" then
        logging.violate("cache.invalid_args", "%s access must be 'reader'", context)
    end
    validateOptionalValue(context .. " fallback", opts.fallback)
    local fallbackValue = copyOptional(opts.fallback)
    local fallbackView = protectOptional(fallbackValue)

    return {
        get = function()
            return readView(id, fallbackView)
        end,
    }
end

return sharedCache
