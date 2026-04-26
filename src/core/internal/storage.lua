local internal = AdamantModpackLib_Internal
internal.storage = internal.storage or {}
local storageInternal = internal.storage
local StorageTypes = storageInternal.types
local libWarn = internal.logging.warnIf
local StorageKey = storageInternal.StorageKey
local NormalizeInteger = storageInternal.NormalizeInteger

---@alias ConfigPath string|string[]
---@alias StorageLifetime "'persistent'"|"'transient'"
---@alias StorageValueKind "'bool'"|"'int'"|"'string'"
---@alias StorageNodeType "'bool'"|"'int'"|"'string'"|"'packedInt'"

---@class PackedBitNode
---@field alias string
---@field label string|nil
---@field type "bool"|"int"
---@field default any
---@field min number|nil
---@field max number|nil
---@field offset number
---@field width number
---@field parent StorageNode|nil
---@field _isBitAlias boolean|nil
---@field _storageKey string|nil
---@field _valueKind StorageValueKind|nil

---@class StorageNode
---@field alias string
---@field label string|nil
---@field type StorageNodeType
---@field configKey ConfigPath|nil
---@field lifetime "transient"|nil
---@field default any
---@field min number|nil
---@field max number|nil
---@field width number|nil
---@field maxLen number|nil
---@field bits PackedBitNode[]|nil
---@field _isRoot boolean|nil
---@field _lifetime "persistent"|"transient"|nil
---@field _storageKey string|nil
---@field _valueKind StorageValueKind|nil
---@field _bitAliases PackedBitNode[]|nil

---@class StorageSchema: StorageNode[]
---@field _rootNodes StorageNode[]|nil
---@field _transientRootNodes StorageNode[]|nil
---@field _aliasNodes table<string, StorageNode|PackedBitNode>|nil
---@field _persistedAliasNodes table<string, StorageNode>|nil
---@field _rootByKey table<string, StorageNode>|nil

local function DeepValueEqual(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end

    for key, value in pairs(a) do
        if not DeepValueEqual(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

local function ReadNestedPath(source, path)
    if type(source) ~= "table" then
        return nil
    end
    if type(path) == "table" then
        local current = source
        for _, key in ipairs(path) do
            if type(current) ~= "table" then
                return nil
            end
            current = current[key]
        end
        return current
    end
    return source[path]
end

function storageInternal.hydrateDefaults(storage, dataDefaults)
    if type(storage) ~= "table" or type(dataDefaults) ~= "table" then
        return storage
    end

    for _, node in ipairs(storage) do
        if type(node) == "table"
            and node.lifetime ~= "transient"
            and node.default == nil
            and node.configKey ~= nil then
            node.default = ReadNestedPath(dataDefaults, node.configKey)
        end
    end

    return storage
end

local function PrepareRootNodeMetadata(node)
    node._storageKey = node.configKey ~= nil and StorageKey(node.configKey) or nil
    if not node.alias and node._storageKey ~= nil then
        node.alias = node._storageKey
    end
end

local function ValidateChildAlias(bitNode, root, storage, seenAliases, seenRootKeys, prefix)
    if type(bitNode.alias) ~= "string" or bitNode.alias == "" then
        return
    end

    if seenAliases[bitNode.alias] then
        libWarn("%s: duplicate alias '%s'", prefix, bitNode.alias)
        return
    end
    local ownerKey = seenRootKeys[bitNode.alias]
    if ownerKey and ownerKey ~= root._storageKey then
        libWarn("%s: alias '%s' conflicts with root configKey '%s'", prefix, bitNode.alias, ownerKey)
        return
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
    storage._aliasNodes[child.alias] = child
    root._bitAliases[#root._bitAliases + 1] = child
end

local function ValidatePackedBits(node, prefix)
    local seenAliases = {}
    local occupiedBits = {}
    for index, bitNode in ipairs(node.bits or {}) do
        local bitPrefix = prefix .. " bits[" .. index .. "]"
        if type(bitNode.alias) ~= "string" or bitNode.alias == "" then
            libWarn("%s: packed bit alias must be a non-empty string", bitPrefix)
        elseif seenAliases[bitNode.alias] then
            libWarn("%s: duplicate packed bit alias '%s'", bitPrefix, bitNode.alias)
        else
            seenAliases[bitNode.alias] = true
        end
        if type(bitNode.offset) ~= "number" or bitNode.offset < 0 then
            libWarn("%s: packed bit offset must be a non-negative number", bitPrefix)
        end
        if type(bitNode.width) ~= "number" or bitNode.width < 1 then
            libWarn("%s: packed bit width must be a positive number", bitPrefix)
        end

        if type(bitNode.offset) == "number" and type(bitNode.width) == "number" then
            local offset = math.floor(bitNode.offset)
            local width = math.floor(bitNode.width)
            if offset + width > 32 then
                libWarn("%s: packed bit offset + width must stay within 32 bits", bitPrefix)
            end
            for bit = offset, offset + width - 1 do
                if occupiedBits[bit] then
                    libWarn("%s: packed bit overlaps bit %d", bitPrefix, bit)
                else
                    occupiedBits[bit] = true
                end
            end
            bitNode.offset = offset
            bitNode.width = width
        end

        local valueType = bitNode.type or (bitNode.width == 1 and "bool" or "int")
        if valueType ~= "bool" and valueType ~= "int" then
            libWarn("%s: packed bit type must be 'bool' or 'int'", bitPrefix)
            valueType = bitNode.width == 1 and "bool" or "int"
        end
        bitNode.type = valueType
        local storageType = StorageTypes[valueType]
        if storageType then
            storageType.validate(bitNode, bitPrefix)
        end
    end
end

local function EnsurePreparedStorage(storage, label)
    if type(storage) ~= "table" then
        return {}
    end
    if rawget(storage, "_aliasNodes") ~= nil and rawget(storage, "_rootNodes") ~= nil then
        return storage._aliasNodes
    end
    storageInternal.validate(storage, label or "storage")
    return storageInternal.getAliases(storage)
end

storageInternal.EnsurePreparedStorage = EnsurePreparedStorage

--- Validates a storage schema and prepares its root, alias, and packed-bit metadata in place.
---@param storage StorageSchema Ordered list of storage root descriptors to validate.
---@param label string Validation label used to prefix warnings.
function storageInternal.validate(storage, label)
    if type(storage) ~= "table" then
        libWarn("%s: storage is not a table", label)
        return
    end

    storage._rootNodes = {}
    storage._transientRootNodes = {}
    storage._aliasNodes = {}
    storage._persistedAliasNodes = {}
    storage._rootByKey = {}

    local seenAliases = {}
    local seenRootKeys = {}

    for index, node in ipairs(storage) do
        local prefix = label .. " storage #" .. index
        if type(node) ~= "table" then
            libWarn("%s: storage entry is not a table", prefix)
        elseif not node.type then
            libWarn("%s: missing type", prefix)
        else
            local storageType = StorageTypes[node.type]
            local isTransient = node.lifetime == "transient"
            if not storageType then
                libWarn("%s: unknown storage type '%s'", prefix, tostring(node.type))
            elseif node.lifetime ~= nil and not isTransient then
                libWarn("%s: unknown lifetime '%s'", prefix, tostring(node.lifetime))
            elseif node.configKey ~= nil and node.lifetime ~= nil then
                libWarn("%s: configKey and lifetime are mutually exclusive", prefix)
            elseif node.configKey == nil and node.lifetime == nil then
                libWarn("%s: storage root must declare configKey or lifetime = 'transient'", prefix)
            elseif isTransient and node.type == "packedInt" then
                libWarn("%s: transient packedInt roots are not supported", prefix)
            elseif not isTransient and node.type == "packedInt" and node.configKey == nil then
                libWarn("%s: packedInt is missing configKey", prefix)
            elseif not isTransient and node.configKey == nil then
                libWarn("%s: missing configKey", prefix)
            else
                storageType.validate(node, prefix)
                PrepareRootNodeMetadata(node)
                node._isRoot = true
                node._lifetime = isTransient and "transient" or "persistent"
                node._valueKind = storageType.valueKind
                node._bitAliases = {}

                if node._storageKey ~= nil then
                    if seenRootKeys[node._storageKey] then
                        libWarn("%s: duplicate configKey '%s'", prefix, node._storageKey)
                    else
                        seenRootKeys[node._storageKey] = node._storageKey
                        storage._rootByKey[node._storageKey] = node
                    end
                end

                local aliasValid = false
                if type(node.alias) ~= "string" or node.alias == "" then
                    libWarn("%s: missing alias", prefix)
                elseif seenAliases[node.alias] then
                    libWarn("%s: duplicate alias '%s'", prefix, node.alias)
                else
                    aliasValid = true
                    seenAliases[node.alias] = true
                    storage._aliasNodes[node.alias] = node
                    if node._lifetime == "persistent" then
                        storage._persistedAliasNodes[node.alias] = node
                    end
                end

                if node.type == "packedInt" then
                    ValidatePackedBits(node, prefix)
                    for bitIndex, bitNode in ipairs(node.bits or {}) do
                        ValidateChildAlias(
                            bitNode,
                            node,
                            storage,
                            seenAliases,
                            seenRootKeys,
                            prefix .. " bits[" .. bitIndex .. "]"
                        )
                    end

                    if node.default == nil then
                        node.default = 0
                        for _, child in ipairs(node._bitAliases) do
                            local encoded = child.type == "bool"
                                and (child.default == true and 1 or 0)
                                or child.default
                            node.default = storageInternal.writePackedBits(node.default, child.offset, child.width, encoded)
                        end
                    else
                        node.default = NormalizeInteger(node, node.default)
                        for _, child in ipairs(node._bitAliases) do
                            if child.default == nil then
                                child.default = storageInternal.readPackedBits(node.default, child.offset, child.width)
                            else
                                local expected = storageInternal.readPackedBits(node.default, child.offset, child.width)
                                local normalized = StorageTypes[child.type].normalize(child, child.default)
                                local encoded = child.type == "bool"
                                    and (normalized == true and 1 or 0)
                                    or normalized
                                if expected ~= encoded then
                                    libWarn("%s: packed child default '%s' does not match packedInt default",
                                        prefix, child.alias)
                                end
                            end
                        end
                    end
                end

                if node._lifetime == "transient" and aliasValid then
                    table.insert(storage._transientRootNodes, node)
                elseif node._lifetime ~= "transient" then
                    table.insert(storage._rootNodes, node)
                end
            end
        end
    end
end

--- Returns the prepared persistent root nodes for a validated storage schema.
---@param storage StorageSchema Validated storage schema.
---@return StorageNode[] roots Prepared list of persistent root storage nodes.
function storageInternal.getRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_rootNodes") or {}
end

--- Compares two values using storage-type equality when available, falling back to deep equality.
---@param node StorageNode|PackedBitNode|nil Storage node whose type-specific equality should be used.
---@param a any First value to compare.
---@param b any Second value to compare.
---@return boolean equal True when the two values are considered equivalent for the storage node.
function storageInternal.valuesEqual(node, a, b)
    local storageType = node and StorageTypes and node.type and StorageTypes[node.type] or nil
    if storageType and type(storageType.equals) == "function" then
        return storageType.equals(node, a, b)
    end
    return DeepValueEqual(a, b)
end

function storageInternal.NormalizeStorageValue(node, value)
    local storageType = node and node.type and storageInternal.types[node.type] or nil
    if storageType and type(storageType.normalize) == "function" then
        return storageType.normalize(node, value)
    end
    return value
end

--- Returns the prepared alias map for a validated storage schema.
---@param storage StorageSchema Validated storage schema.
---@return table<string, StorageNode|PackedBitNode> aliases Map from storage alias to prepared storage node.
function storageInternal.getAliases(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_aliasNodes") or {}
end
