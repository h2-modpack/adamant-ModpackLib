local deps = ...

local logging = deps.logging
local identifiers = deps.identifiers
local StorageTypes = deps.types
local NormalizeInteger = deps.NormalizeInteger
local nodeOps = deps.nodeOps
local packed = deps.packed
local tableStorage = deps.tableStorage
local schema = {}

-- Storage schemas are prepared once by prepareDefinition, then treated as
-- runtime-stable metadata by store/staged-state/modpack consumers. Validation is
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

function schema.isPrivateAlias(value)
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

local function ValidateKnownFields(node, allowedFields, prefix)
    for key in pairs(node) do
        if not nodeOps.isInternalField(key) and not allowedFields[key] and not CommonNodeFields[key] then
            logging.violate("storage.unknown_field", "%s: unknown storage field '%s'", prefix, tostring(key))
        end
    end
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

local function IsTrustedSystemAlias(node, opts)
    local systemNodes = opts and opts.systemNodes or nil
    return type(node) == "table" and systemNodes ~= nil and systemNodes[node] == true
end

local function ValidateAliasIdentifier(node, alias, prefix, opts)
    if IsTrustedSystemAlias(node, opts) then
        return
    end

    if IsTrustedInternalAlias(node, opts) then
        if not identifiers.isInternal(alias) then
            logging.violate("storage.invalid_node", "%s: internal alias '%s' %s",
                prefix, tostring(alias), identifiers.INTERNAL_DESCRIPTION)
        end
        return
    end

    if not identifiers.isStable(alias) then
        logging.violate("storage.invalid_node", "%s: alias '%s' %s",
            prefix, tostring(alias), identifiers.STABLE_DESCRIPTION)
    end
end

-- Runs after packed.validatePackedBits, so bit aliases are non-empty strings and bit types are known.
local function PreparePackedChildAlias(bitNode, root, storageSchema, seenAliases, prefix, opts)
    ValidateAliasIdentifier(bitNode, bitNode.alias, prefix, opts)

    if seenAliases[bitNode.alias] then
        logging.violate("storage.duplicate_alias", "%s: duplicate alias '%s'", prefix, bitNode.alias)
    end

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
    for _, root in ipairs(storageSchema._persistRootNodes) do
        if root.default == nil then
            logging.violate(
                "storage.missing_persisted_default",
                "%s: persisted storage alias '%s' must declare an effective default",
                prefix,
                root.alias
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
                node._storageKey = node.alias
                node._persist = persist
                node._hash = hash
                node._mode = mode
                node._bitAliases = {}

                if seenAliases[node.alias] then
                    logging.violate("storage.duplicate_alias", "%s: duplicate alias '%s'", prefix, node.alias)
                end
                seenAliases[node.alias] = true
                storageSchema._aliasNodes[node.alias] = node

                if node.type == "packedInt" then
                    packed.validatePackedBits(node, prefix)
                    for bitIndex, bitNode in ipairs(node.bits) do
                        PreparePackedChildAlias(
                            bitNode,
                            node,
                            storageSchema,
                            seenAliases,
                            prefix .. " bits[" .. bitIndex .. "]",
                            opts
                        )
                    end
                    local maxPackedValue = packed.GetBitValueMask(node.width)

                    if node.default == nil then
                        node.default = 0
                        for _, child in ipairs(node._bitAliases) do
                            node.default = packed.writePackedBits(node.default, child.offset, child.width,
                                packed.encodeChild(child, child.default))
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
                                local normalized = nodeOps.normalize(child, child.default)
                                if expected ~= packed.encodeChild(child, normalized) then
                                    logging.violate(
                                        "storage.packed_child_default_mismatch",
                                        "%s: packed child default '%s' does not match packedInt default",
                                        prefix, child.alias)
                                end
                            end
                        end
                    end
                elseif node.type == "table" then
                    tableStorage.ValidateRowDeclarations(node, prefix)
                    schema.validate(node.row, prefix .. " row", opts)
                    tableStorage.PrepareTableNode(node)
                end
                if node._persist then
                    table.insert(storageSchema._persistRootNodes, node)
                end
                table.insert(storageSchema._stagedRootNodes, node)
                if node._hash then
                    table.insert(storageSchema._rootNodes, node)
                end
            end
        end
    end

    ValidatePersistedDefaults(storageSchema, label)
end

function schema.getRoots(storageSchema)
    return storageSchema._rootNodes
end

function schema.getPersistRoots(storageSchema)
    return storageSchema._persistRootNodes
end

function schema.getStagedRoots(storageSchema)
    return storageSchema._stagedRootNodes
end

function schema.getAliases(storageSchema)
    return storageSchema._aliasNodes
end

return schema
