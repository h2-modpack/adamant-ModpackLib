local deps = ...

local logging = deps.logging
local snapshotObject = deps.snapshotObject
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

local function copyOptional(value)
    if value == nil then
        return nil
    end
    return values.deepCopy(value)
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

function sharedCache.stagePublication(record, host, id, opts)
    local context = "host.cache.shared.publish"
    validateId(context, id)
    if opts ~= nil and type(opts) ~= "table" then
        logging.violate("cache.invalid_args", "%s opts must be a table when provided", context)
    end
    opts = opts or {}
    if opts.default ~= nil then
        validateValue(context .. " default", opts.default)
    end

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
                    hasDefault = entry.hasDefault == true,
                    value = nil,
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

function sharedCache.write(ownerId, ownerToken, id, value)
    local record = requireOwnerRecord("cache.shared.write", ownerId, ownerToken, id)
    validateValue("cache.shared.write", value)
    record.value = values.deepCopy(value)
    record.hasValue = true
    return true
end

function sharedCache.clear(ownerId, ownerToken, id)
    local record = requireOwnerRecord("cache.shared.clear", ownerId, ownerToken, id)
    record.value = nil
    record.hasValue = false
    return true
end

function sharedCache.read(id, fallback)
    validateId("cache.shared.read", id)
    local record = records[id]
    if not record or not (record.isEnabled and record.isEnabled()) then
        return values.deepCopy(fallback)
    end
    if record.hasValue then
        return values.deepCopy(record.value)
    end
    if record.hasDefault then
        return values.deepCopy(record.default)
    end
    return values.deepCopy(fallback)
end

function sharedCache.createOwner(record, host, id, opts)
    local context = "host.cache.shared.create"
    if opts ~= nil and type(opts) ~= "table" then
        logging.violate("cache.invalid_args", "%s opts must be a table when provided", context)
    end
    opts = opts or {}
    if opts.access ~= nil and opts.access ~= "owner" then
        logging.violate("cache.invalid_args", "%s access must be 'owner'", context)
    end

    sharedCache.stagePublication(record, host, id, {
        default = opts.default,
    })

    local publications = ensurePublicationSet(record)
    return snapshotObject.create({
        load = function()
            return copyOptional(opts.default)
        end,
        write = function(value)
            local ok = sharedCache.write(host.getHostId(), publications.ownerToken, id, value)
            return ok, copyOptional(value)
        end,
        clear = function()
            local ok = sharedCache.clear(host.getHostId(), publications.ownerToken, id)
            return ok, copyOptional(opts.default)
        end,
        refresh = function()
            return sharedCache.read(id, opts.default)
        end,
    })
end

function sharedCache.createReader(id, opts)
    local context = "host.cache.shared.create"
    validateId(context, id)
    if opts ~= nil and type(opts) ~= "table" then
        logging.violate("cache.invalid_args", "%s opts must be a table when provided", context)
    end
    opts = opts or {}
    if opts.access ~= nil and opts.access ~= "reader" then
        logging.violate("cache.invalid_args", "%s access must be 'reader'", context)
    end

    return snapshotObject.create({
        load = function()
            return sharedCache.read(id, opts.fallback)
        end,
    })
end

return sharedCache
