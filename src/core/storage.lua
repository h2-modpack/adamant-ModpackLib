local internal = AdamantModpackLib_Internal
internal.storage = internal.storage or {}
local storageInternal = internal.storage
local StorageTypes = {}
storageInternal.types = StorageTypes
local libWarn = internal.logging.warnIf
local StorageKey = storageInternal.StorageKey
local NormalizeInteger = storageInternal.NormalizeInteger

public.storage = public.storage or {}
local storageApi = public.storage

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

local function GetBitValueMask(width)
    local normalizedWidth = math.floor(tonumber(width) or 0)
    if normalizedWidth <= 0 then return 0 end
    if normalizedWidth >= 32 then return 0xFFFFFFFF end
    return bit32.rshift(0xFFFFFFFF, 32 - normalizedWidth)
end

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

local function EnsurePreparedStorage(storage, label)
    if type(storage) ~= "table" then
        return {}
    end
    if rawget(storage, "_aliasNodes") ~= nil and rawget(storage, "_rootNodes") ~= nil then
        return storage._aliasNodes
    end
    storageApi.validate(storage, label or "storage")
    return storageApi.getAliases(storage)
end

storageInternal.EnsurePreparedStorage = EnsurePreparedStorage

StorageTypes.bool = {
    valueKind = "bool",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "boolean" then
            libWarn("%s: bool default must be boolean, got %s", prefix, type(node.default))
        end
    end,
    normalize = function(_, value)
        return value == true
    end,
    toHash = function(_, value)
        return value and "1" or "0"
    end,
    fromHash = function(_, str)
        return str == "1"
    end,
    packWidth = function(_)
        return 1
    end,
}

StorageTypes.int = {
    valueKind = "int",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "number" then
            libWarn("%s: int default must be number, got %s", prefix, type(node.default))
        end
        if node.min ~= nil and type(node.min) ~= "number" then
            libWarn("%s: int min must be number, got %s", prefix, type(node.min))
        end
        if node.max ~= nil and type(node.max) ~= "number" then
            libWarn("%s: int max must be number, got %s", prefix, type(node.max))
        end
        if type(node.min) == "number" and type(node.max) == "number" and node.min > node.max then
            libWarn("%s: int min cannot exceed max", prefix)
        end
        if node.width ~= nil and (type(node.width) ~= "number" or node.width < 1) then
            libWarn("%s: int width must be a positive number", prefix)
        end
    end,
    normalize = function(node, value)
        return NormalizeInteger(node, value)
    end,
    toHash = function(node, value)
        return tostring(NormalizeInteger(node, value))
    end,
    fromHash = function(node, str)
        return NormalizeInteger(node, tonumber(str))
    end,
    packWidth = function(node)
        if type(node.width) == "number" and node.width >= 1 then
            return math.floor(node.width)
        end
        if type(node.min) == "number" and type(node.max) == "number" then
            local range = node.max - node.min
            if range <= 0 then return 1 end
            return math.ceil(math.log(range + 1) / math.log(2))
        end
        return nil
    end,
}

StorageTypes.string = {
    valueKind = "string",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "string" then
            libWarn("%s: string default must be string, got %s", prefix, type(node.default))
        end
        if node.maxLen ~= nil and (type(node.maxLen) ~= "number" or node.maxLen < 1) then
            libWarn("%s: string maxLen must be a positive number", prefix)
        end
        node._maxLen = math.floor(tonumber(node.maxLen) or 256)
        if node._maxLen < 1 then node._maxLen = 256 end
    end,
    normalize = function(node, value)
        return value ~= nil and tostring(value) or (node.default or "")
    end,
    toHash = function(_, value)
        return tostring(value or "")
    end,
    fromHash = function(node, str)
        return str ~= nil and tostring(str) or (node.default or "")
    end,
}

StorageTypes.packedInt = {
    valueKind = "int",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "number" then
            libWarn("%s: packedInt default must be number, got %s", prefix, type(node.default))
        end
        if node.width ~= nil and (type(node.width) ~= "number" or node.width < 1 or node.width > 32) then
            libWarn("%s: packedInt width must be a positive number no greater than 32", prefix)
        end
        if type(node.bits) ~= "table" or #node.bits == 0 then
            libWarn("%s: packedInt bits must be a non-empty list", prefix)
            return
        end

        local seenAliases = {}
        local occupiedBits = {}
        for index, bitNode in ipairs(node.bits) do
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
    end,
    normalize = function(node, value)
        return NormalizeInteger(node, value)
    end,
    toHash = function(node, value)
        return tostring(NormalizeInteger(node, value))
    end,
    fromHash = function(node, str)
        return NormalizeInteger(node, tonumber(str))
    end,
    packWidth = function(node)
        if type(node.width) == "number" and node.width >= 1 and node.width <= 32 then
            return math.floor(node.width)
        end
        if type(node.bits) ~= "table" then
            return nil
        end
        local maxUsedBit = 0
        for _, bitNode in ipairs(node.bits) do
            if type(bitNode.offset) == "number" and type(bitNode.width) == "number" then
                local used = math.floor(bitNode.offset) + math.floor(bitNode.width)
                if used > maxUsedBit then
                    maxUsedBit = used
                end
            end
        end
        if maxUsedBit > 0 and maxUsedBit <= 32 then
            return maxUsedBit
        end
        return nil
    end,
}

--- Validates a storage schema and prepares its root, alias, and packed-bit metadata in place.
---@param storage StorageSchema Ordered list of storage root descriptors to validate.
---@param label string Validation label used to prefix warnings.
function storageApi.validate(storage, label)
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
                            node.default = storageApi.writePackedBits(node.default, child.offset, child.width, encoded)
                        end
                    else
                        node.default = NormalizeInteger(node, node.default)
                        for _, child in ipairs(node._bitAliases) do
                            if child.default == nil then
                                child.default = storageApi.readPackedBits(node.default, child.offset, child.width)
                            else
                                local expected = storageApi.readPackedBits(node.default, child.offset, child.width)
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
function storageApi.getRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_rootNodes") or {}
end

--- Returns the packed width contributed by a storage node, when the node type supports packing.
---@param node StorageNode|PackedBitNode Storage node to inspect.
---@return number|nil width Packed width in bits, or nil when the node is not packable.
function storageApi.getPackWidth(node)
    if type(node) ~= "table" then return nil end
    local storageType = StorageTypes[node.type]
    if storageType and storageType.packWidth then
        return storageType.packWidth(node)
    end
    return nil
end

--- Compares two values using storage-type equality when available, falling back to deep equality.
---@param node StorageNode|PackedBitNode|nil Storage node whose type-specific equality should be used.
---@param a any First value to compare.
---@param b any Second value to compare.
---@return boolean equal True when the two values are considered equivalent for the storage node.
function storageApi.valuesEqual(node, a, b)
    local storageType = node and StorageTypes and node.type and StorageTypes[node.type] or nil
    if storageType and type(storageType.equals) == "function" then
        return storageType.equals(node, a, b)
    end
    return DeepValueEqual(a, b)
end

--- Encodes a storage value into its hash string form using the node's storage type.
---@param node StorageNode|PackedBitNode Storage node whose type-specific hash encoder should be used.
---@param value any Value to encode.
---@return string|nil encoded Encoded hash value, or nil when the node type is unknown.
function storageApi.toHash(node, value)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType or type(storageType.toHash) ~= "function" then
        return nil
    end
    return storageType.toHash(node, value)
end

--- Decodes a storage value from its hash string form using the node's storage type.
---@param node StorageNode|PackedBitNode Storage node whose type-specific hash decoder should be used.
---@param str string Encoded hash value.
---@return any decoded Decoded value, or nil when the node type is unknown.
function storageApi.fromHash(node, str)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType or type(storageType.fromHash) ~= "function" then
        return nil
    end
    return storageType.fromHash(node, str)
end

--- Returns the prepared alias map for a validated storage schema.
---@param storage StorageSchema Validated storage schema.
---@return table<string, StorageNode|PackedBitNode> aliases Map from storage alias to prepared storage node.
function storageApi.getAliases(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_aliasNodes") or {}
end

--- Reads a bitfield value from a packed integer using an offset and width.
---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@return number
function storageApi.readPackedBits(packed, offset, width)
    local normalizedPacked = math.floor(tonumber(packed) or 0)
    local normalizedOffset = math.max(0, math.floor(tonumber(offset) or 0))
    local mask = GetBitValueMask(width)
    if mask == 0 then return 0 end
    return bit32.band(bit32.rshift(normalizedPacked, normalizedOffset), mask)
end

--- Writes a bitfield value into a packed integer using an offset and width.
---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@param value number|nil
---@return number
function storageApi.writePackedBits(packed, offset, width, value)
    local normalizedPacked = math.floor(tonumber(packed) or 0)
    local normalizedOffset = math.max(0, math.floor(tonumber(offset) or 0))
    local mask = GetBitValueMask(width)
    if mask == 0 then return normalizedPacked end
    local normalizedValue = math.floor(tonumber(value) or 0)
    if normalizedValue < 0 then normalizedValue = 0
    elseif normalizedValue > mask then normalizedValue = mask end
    local shiftedMask = bit32.lshift(mask, normalizedOffset)
    local cleared = bit32.band(normalizedPacked, bit32.bnot(shiftedMask))
    return bit32.bor(cleared, bit32.lshift(normalizedValue, normalizedOffset))
end
