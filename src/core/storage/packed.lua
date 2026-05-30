local deps = ...

local logging = deps.logging
local storage = deps.storage
local StorageTypes = deps.types
local EMPTY_LIST = {}

local PackedBitFields = {
    alias = true,
    default = true,
    label = true,
    max = true,
    min = true,
    offset = true,
    tooltip = true,
    type = true,
    width = true,
}

local function IsInternalField(key)
    return type(key) == "string" and string.sub(key, 1, 1) == "_"
end

local function ValidateKnownPackedBitFields(node, prefix)
    for key in pairs(node) do
        if not IsInternalField(key) and not PackedBitFields[key] then
            logging.violate("storage.unknown_field", "%s: unknown packed bit field '%s'", prefix, tostring(key))
        end
    end
end

local function GetBitValueMask(width)
    local normalizedWidth = math.floor(tonumber(width) or 0)
    if normalizedWidth <= 0 then return 0 end
    if normalizedWidth >= 32 then return 0xFFFFFFFF end
    return bit32.rshift(0xFFFFFFFF, 32 - normalizedWidth)
end

---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@return number
local function readPackedBits(packedValue, offset, width)
    local normalizedPacked = math.floor(tonumber(packedValue) or 0)
    local normalizedOffset = math.max(0, math.floor(tonumber(offset) or 0))
    local mask = GetBitValueMask(width)
    if mask == 0 then return 0 end
    return bit32.band(bit32.rshift(normalizedPacked, normalizedOffset), mask)
end

---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@param value number|nil
---@return number
local function writePackedBits(packedValue, offset, width, value)
    local normalizedPacked = math.floor(tonumber(packedValue) or 0)
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

---@param node StorageNode
---@param prefix string
local function validatePackedBits(node, prefix)
    local seenAliases = {}
    local occupiedBits = {}
    local rootWidth = math.floor(tonumber(node.width) or 0)
    for index, bitNode in ipairs(node.bits or {}) do
        local bitPrefix = prefix .. " bits[" .. index .. "]"
        ValidateKnownPackedBitFields(bitNode, bitPrefix)
        if type(bitNode.alias) ~= "string" or bitNode.alias == "" then
            logging.violate("storage.invalid_packed_bit", "%s: packed bit alias must be a non-empty string", bitPrefix)
        elseif seenAliases[bitNode.alias] then
            logging.violate("storage.duplicate_alias", "%s: duplicate packed bit alias '%s'", bitPrefix, bitNode.alias)
        else
            seenAliases[bitNode.alias] = true
        end
        if type(bitNode.offset) ~= "number" or bitNode.offset < 0 then
            logging.violate("storage.invalid_packed_bit", "%s: packed bit offset must be a non-negative number", bitPrefix)
        end
        if type(bitNode.width) ~= "number" or bitNode.width < 1 or not storage.IsInteger(bitNode.width) then
            logging.violate("storage.invalid_packed_bit", "%s: packed bit width must be a positive integer", bitPrefix)
        end

        if type(bitNode.offset) == "number" and type(bitNode.width) == "number" then
            local offset = math.floor(bitNode.offset)
            local width = math.floor(bitNode.width)
            if not storage.IsInteger(bitNode.offset) then
                logging.violate("storage.invalid_packed_bit", "%s: packed bit offset must be an integer", bitPrefix)
            end
            if offset + width > rootWidth then
                logging.violate(
                    "storage.invalid_packed_bit",
                    "%s: packed bit offset + width must stay within packedInt width %d",
                    bitPrefix,
                    rootWidth
                )
            end
            for bit = offset, offset + width - 1 do
                if occupiedBits[bit] then
                    logging.violate("storage.invalid_packed_bit", "%s: packed bit overlaps bit %d", bitPrefix, bit)
                else
                    occupiedBits[bit] = true
                end
            end
            bitNode.offset = offset
            bitNode.width = width
        end

        local valueType = bitNode.type or (bitNode.width == 1 and "bool" or "int")
        if valueType ~= "bool" and valueType ~= "int" then
            logging.violate("storage.invalid_packed_bit", "%s: packed bit type must be 'bool' or 'int'", bitPrefix)
        end
        bitNode.type = valueType
        if valueType == "bool" and bitNode.width ~= 1 then
            logging.violate("storage.invalid_packed_bit", "%s: bool packed bit width must be 1", bitPrefix)
        end
        local storageType = StorageTypes[valueType]
        if storageType then
            storageType.validate(bitNode, bitPrefix)
        end
        if valueType == "int" then
            local mask = GetBitValueMask(bitNode.width)
            if bitNode.min ~= nil and bitNode.min < 0 then
                logging.violate("storage.invalid_packed_bit", "%s: packed int bit min cannot be negative", bitPrefix)
            end
            if bitNode.max ~= nil and bitNode.max > mask then
                logging.violate("storage.invalid_packed_bit", "%s: packed int bit max exceeds declared bit width", bitPrefix)
            end
            local default = StorageTypes.int.normalize(bitNode, bitNode.default)
            if default < 0 or default > mask then
                logging.violate("storage.invalid_packed_bit", "%s: packed int bit default exceeds declared bit width", bitPrefix)
            end
        end
    end
end

---@param node PackedBitNode
---@param packedValue number|nil
---@return any
local function DecodePackedChild(node, packedValue)
    local rawValue = readPackedBits(packedValue, node.offset, node.width)
    if node.type == "bool" then
        rawValue = rawValue ~= 0
    end
    return storage.NormalizeStorageValue(node, rawValue)
end

---@param node StorageNode|PackedBitNode|nil
---@return table[] aliases
local function getPackedAliases(node)
    if not node or node.type ~= "packedInt" then
        return EMPTY_LIST
    end

    if node._packedAliasViews then
        return node._packedAliasViews
    end

    local packedAliases = {}
    for _, child in ipairs(node._bitAliases or {}) do
        packedAliases[#packedAliases + 1] = {
            alias = child.alias,
            label = child.label or child.alias,
            node = child,
        }
    end
    node._packedAliasViews = packedAliases
    return packedAliases
end

return {
    GetBitValueMask = GetBitValueMask,
    readPackedBits = readPackedBits,
    writePackedBits = writePackedBits,
    validatePackedBits = validatePackedBits,
    DecodePackedChild = DecodePackedChild,
    getPackedAliases = getPackedAliases,
}
