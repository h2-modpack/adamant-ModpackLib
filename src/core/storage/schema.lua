local deps = ...

local logging = deps.logging
local values = deps.values
local storage = deps.storage
local packed = deps.packed
local tableStorage = deps.tableStorage
local schema = {}

local StorageTypes = storage.types
local NormalizeInteger = storage.NormalizeInteger

-- Storage schemas are prepared once by prepareDefinition, then treated as
-- runtime-stable metadata by store/staged-state/Framework consumers. Validation is
-- fail-fast: the first structural contract violation stops preparation.
--
-- Supported root-axis combinations:
--   persist=true,  hash=true   -> config-backed UI/profile/hash state.
--   persist=true,  hash=false  -> config-backed UI state excluded from hashes.
--   persist=false, hash=false  -> transient staged-only UI state.
--   mode=runtime               -> status state; hash=false required.
--
-- hash=true requires persist=true. Table rows inherit their table root axes.

local CommonNodeFields = {
    alias = true,
    default = true,
    hash = true,
    label = true,
    mode = true,
    persist = true,
    tooltip = true,
    type = true,
}

local StableIdentifierPattern = "^[A-Za-z][A-Za-z0-9_]*$"
local StableIdentifierDescription = "must start with a letter and contain only letters, digits, and underscores"
local InternalPathSeparator = "-"
local InternalIdentifierDescription =
    "must start with '_' and contain '-'-separated stable identifier segments"

local function IsStableIdentifier(value)
    return type(value) == "string" and string.match(value, StableIdentifierPattern) ~= nil
end

local function IsInternalIdentifier(value)
    if type(value) ~= "string" or string.byte(value, 1) ~= 95 then
        return false
    end

    local rest = string.sub(value, 2)
    if rest == "" then
        return false
    end

    local segmentStart = 1
    while true do
        local separatorStart, separatorEnd = string.find(rest, InternalPathSeparator, segmentStart, true)
        local segment = separatorStart ~= nil
            and string.sub(rest, segmentStart, separatorStart - 1)
            or string.sub(rest, segmentStart)
        if not IsStableIdentifier(segment) then
            return false
        end
        if separatorStart == nil then
            return true
        end
        segmentStart = separatorEnd + 1
    end
end

local function IsPrivateAlias(value)
    return type(value) == "string" and string.byte(value, 1) == 95
end

local RootNodeFieldsByType = {
    bool = {},
    int = {
        max = true,
        min = true,
    },
    string = {
        maxLen = true,
    },
    packedInt = {
        bits = true,
        width = true,
    },
    table = {
        defaultRows = true,
        maxRows = true,
        minRows = true,
        row = true,
    },
}

local function IsInternalField(key)
    return type(key) == "string" and string.sub(key, 1, 1) == "_"
end

local function ValidateKnownFields(node, allowedFields, prefix)
    for key in pairs(node) do
        if not IsInternalField(key) and not allowedFields[key] and not CommonNodeFields[key] then
            logging.violate("storage.unknown_field", "%s: unknown storage field '%s'", prefix, tostring(key))
        end
    end
end

local function PrepareRootNodeMetadata(node)
    node._storageKey = node.alias
end

local function NormalizeMode(prefix, mode)
    if mode == nil then
        return "setting"
    end
    if mode ~= "setting" and mode ~= "runtime" then
        logging.violate("storage.invalid_axis_type", "%s: mode must be 'setting' or 'runtime'", prefix)
    end
    return mode
end

local function IsTrustedInternalAlias(node, opts)
    local internalNodes = opts and opts.internalNodes or nil
    return type(node) == "table" and internalNodes ~= nil and internalNodes[node] == true
end

local function ValidateAliasIdentifier(node, alias, prefix, opts)
    if IsTrustedInternalAlias(node, opts) then
        if not IsInternalIdentifier(alias) then
            logging.violate("storage.invalid_node", "%s: internal alias '%s' %s",
                prefix, tostring(alias), InternalIdentifierDescription)
        end
        return
    end

    if not IsStableIdentifier(alias) then
        logging.violate("storage.invalid_node", "%s: alias '%s' %s",
            prefix, tostring(alias), StableIdentifierDescription)
    end
end

local function PreparePackedChildAlias(bitNode, root, storageSchema, seenAliases, seenRootKeys, prefix, opts)
    if type(bitNode.alias) ~= "string" or bitNode.alias == "" then
        return
    end
    ValidateAliasIdentifier(bitNode, bitNode.alias, prefix, opts)

    if seenAliases[bitNode.alias] then
        logging.violate("storage.duplicate_alias", "%s: duplicate alias '%s'", prefix, bitNode.alias)
    end
    local ownerKey = seenRootKeys[bitNode.alias]
    if ownerKey and ownerKey ~= root._storageKey then
        logging.violate("storage.duplicate_alias", "%s: alias '%s' conflicts with root alias '%s'", prefix, bitNode.alias, ownerKey)
    end

    local storageType = StorageTypes[bitNode.type]
    local child = {
        alias = bitNode.alias,
        label = bitNode.label or bitNode.alias,
        type = bitNode.type,
        default = bitNode.default,
        min = bitNode.min,
        max = bitNode.max,
        offset = bitNode.offset,
        width = bitNode.width,
        parent = root,
        _isBitAlias = true,
        _persist = root._persist,
        _hash = root._hash,
        _mode = root._mode,
        _storageKey = root._storageKey .. "." .. bitNode.alias,
        _valueKind = storageType and storageType.valueKind or bitNode.type,
    }
    if child.type == "bool" and child.default == nil then
        child.default = false
    end
    if child.type == "int" and child.default == nil then
        child.default = 0
    end

    seenAliases[child.alias] = true
    storageSchema._aliasNodes[child.alias] = child
    root._bitAliases[#root._bitAliases + 1] = child
end

local function ValidatePersistedDefaults(storageSchema, label)
    local prefix = label or "storage"
    for _, root in ipairs(rawget(storageSchema, "_persistRootNodes") or {}) do
        if root.default == nil then
            logging.violate(
                "storage.missing_persisted_default",
                "%s: persisted storage alias '%s' must declare an effective default",
                prefix,
                tostring(root.alias or "<unknown>")
            )
        end
    end
end

function schema.validate(storageSchema, label, opts)
    if type(storageSchema) ~= "table" then
        logging.violate("storage.invalid_schema", "%s: storage is not a table", label)
    end

    storageSchema._rootNodes = {}
    storageSchema._persistRootNodes = {}
    storageSchema._stagedRootNodes = {}
    storageSchema._aliasNodes = {}

    local seenAliases = {}
    local seenRootKeys = {}

    for index, node in ipairs(storageSchema) do
        local prefix = label .. " storage #" .. index
        if type(node) ~= "table" then
            logging.violate("storage.invalid_node", "%s: storage entry is not a table", prefix)
        elseif not node.type then
            logging.violate("storage.invalid_node", "%s: missing type", prefix)
        else
            local storageType = StorageTypes[node.type]
            local mode = NormalizeMode(prefix, node.mode)
            local persist = node.persist ~= false
            local hash
            if mode == "runtime" then
                hash = false
            else
                hash = persist and node.hash ~= false or node.hash == true
            end
            if not storageType then
                logging.violate("storage.invalid_node", "%s: unknown storage type '%s'", prefix, tostring(node.type))
            elseif node.persist ~= nil and type(node.persist) ~= "boolean" then
                logging.violate("storage.invalid_axis_type", "%s: persist must be boolean when provided", prefix)
            elseif node.hash ~= nil and type(node.hash) ~= "boolean" then
                logging.violate("storage.invalid_axis_type", "%s: hash must be boolean when provided", prefix)
            elseif mode == "runtime" and node.hash == true then
                logging.violate("storage.hash_requires_setting", "%s: mode='runtime' requires hash=false", prefix)
            elseif type(node.alias) ~= "string" or node.alias == "" then
                logging.violate("storage.invalid_node", "%s: missing alias", prefix)
            elseif hash and not persist then
                logging.violate("storage.hash_requires_persist", "%s: hash=true requires persist=true", prefix)
            else
                ValidateKnownFields(node, RootNodeFieldsByType[node.type] or {}, prefix)
                storageType.validate(node, prefix)
                ValidateAliasIdentifier(node, node.alias, prefix, opts)
                PrepareRootNodeMetadata(node)
                node._isRoot = true
                node._persist = persist
                node._hash = hash
                node._mode = mode
                node._valueKind = storageType.valueKind
                node._bitAliases = {}

                if node._storageKey ~= nil then
                    if not seenRootKeys[node._storageKey] then
                        seenRootKeys[node._storageKey] = node._storageKey
                    end
                end

                local aliasValid = false
                if seenAliases[node.alias] then
                    logging.violate("storage.duplicate_alias", "%s: duplicate alias '%s'", prefix, node.alias)
                else
                    aliasValid = true
                    seenAliases[node.alias] = true
                    storageSchema._aliasNodes[node.alias] = node
                end

                if node.type == "packedInt" then
                    packed.validatePackedBits(node, prefix)
                    for bitIndex, bitNode in ipairs(node.bits or {}) do
                        PreparePackedChildAlias(
                            bitNode,
                            node,
                            storageSchema,
                            seenAliases,
                            seenRootKeys,
                            prefix .. " bits[" .. bitIndex .. "]",
                            opts
                        )
                    end
                    local maxPackedValue = packed.GetBitValueMask(node.width)

                    if node.default == nil then
                        node.default = 0
                        for _, child in ipairs(node._bitAliases) do
                            local encoded = child.type == "bool"
                                and (child.default == true and 1 or 0)
                                or child.default
                            node.default = packed.writePackedBits(node.default, child.offset, child.width, encoded)
                        end
                    else
                        node.default = NormalizeInteger(node, node.default)
                        if node.default < 0 or node.default > maxPackedValue then
                            logging.violate(
                                "storage.invalid_default",
                                "%s: packedInt default exceeds declared width",
                                prefix
                            )
                        end
                        for _, child in ipairs(node._bitAliases) do
                            if child.default == nil then
                                child.default = packed.readPackedBits(node.default, child.offset, child.width)
                            else
                                local expected = packed.readPackedBits(node.default, child.offset, child.width)
                                local normalized = StorageTypes[child.type].normalize(child, child.default)
                                local encoded = child.type == "bool"
                                    and (normalized == true and 1 or 0)
                                    or normalized
                                if expected ~= encoded then
                                    logging.violate(
                                        "storage.packed_child_default_mismatch",
                                        "%s: packed child default '%s' does not match packedInt default",
                                        prefix, child.alias)
                                end
                            end
                        end
                    end
                elseif node.type == "table" then
                    tableStorage.PrepareTableNode(node, prefix, opts)
                end
                if node._persist then
                    table.insert(storageSchema._persistRootNodes, node)
                end
                table.insert(storageSchema._stagedRootNodes, node)
                if node._hash and aliasValid then
                    table.insert(storageSchema._rootNodes, node)
                end
            end
        end
    end

    ValidatePersistedDefaults(storageSchema, label)
end

function schema.isPrivateAlias(alias)
    return IsPrivateAlias(alias)
end

function schema.getRoots(storageSchema)
    if type(storageSchema) ~= "table" then return {} end
    return rawget(storageSchema, "_rootNodes") or {}
end

function schema.getPersistRoots(storageSchema)
    if type(storageSchema) ~= "table" then return {} end
    return rawget(storageSchema, "_persistRootNodes") or {}
end

function schema.getStagedRoots(storageSchema)
    if type(storageSchema) ~= "table" then return {} end
    return rawget(storageSchema, "_stagedRootNodes") or {}
end

function schema.getAliases(storageSchema)
    if type(storageSchema) ~= "table" then return {} end
    return rawget(storageSchema, "_aliasNodes") or {}
end

function schema.valuesEqual(node, a, b)
    local storageType = node and StorageTypes and node.type and StorageTypes[node.type] or nil
    if storageType and storageType.equals ~= nil then
        return storageType.equals(node, a, b)
    end
    return values.deepEqual(a, b)
end

function schema.NormalizeStorageValue(node, value)
    local storageType = node and node.type and storage.types[node.type] or nil
    if storageType and storageType.normalize ~= nil then
        return storageType.normalize(node, value)
    end
    return value
end

function schema.toHash(node, value)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.toHash(node, value)
end

function schema.fromHash(node, str)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.fromHash(node, str)
end

function schema.isHashTokenValid(node, str)
    local storageType = node and StorageTypes and node.type and StorageTypes[node.type] or nil
    if storageType and storageType.isHashTokenValid ~= nil then
        return storageType.isHashTokenValid(node, str)
    end
    return str ~= nil
end

return schema
