local deps = ...

local logging = deps.logging
local storage = deps.storage
local values = deps.values
local StorageTypes = {}

local function IsInteger(value)
    return type(value) == "number" and value == math.floor(value)
end

local function NormalizeInteger(node, value)
    local num = tonumber(value)
    if num == nil then
        num = tonumber(node.default) or 0
    end
    num = math.floor(num)
    if node.min ~= nil and num < node.min then num = node.min end
    if node.max ~= nil and num > node.max then num = node.max end
    return num
end

local function GetStringMaxLen(node)
    local maxLen = math.floor(tonumber(node._maxLen or node.maxLen) or 256)
    if maxLen < 1 then
        return 256
    end
    return maxLen
end

local function NormalizeString(node, value)
    local text = value ~= nil and tostring(value) or (node.default or "")
    local maxLen = GetStringMaxLen(node)
    if #text > maxLen then
        return string.sub(text, 1, maxLen)
    end
    return text
end

StorageTypes.bool = {
    valueKind = "bool",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "boolean" then
            logging.violate("storage.invalid_default", "%s: bool default must be boolean, got %s", prefix, type(node.default))
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
    isHashTokenValid = function(_, str)
        return str == "0" or str == "1"
    end,
    packWidth = function(_)
        return 1
    end,
}

StorageTypes.int = {
    valueKind = "int",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "number" then
            logging.violate("storage.invalid_default", "%s: int default must be number, got %s", prefix, type(node.default))
        elseif node.default ~= nil and not IsInteger(node.default) then
            logging.violate("storage.invalid_default", "%s: int default must be an integer", prefix)
        end
        if node.min ~= nil and type(node.min) ~= "number" then
            logging.violate("storage.invalid_axis_type", "%s: int min must be number, got %s", prefix, type(node.min))
        elseif node.min ~= nil and not IsInteger(node.min) then
            logging.violate("storage.invalid_axis_type", "%s: int min must be an integer", prefix)
        end
        if node.max ~= nil and type(node.max) ~= "number" then
            logging.violate("storage.invalid_axis_type", "%s: int max must be number, got %s", prefix, type(node.max))
        elseif node.max ~= nil and not IsInteger(node.max) then
            logging.violate("storage.invalid_axis_type", "%s: int max must be an integer", prefix)
        end
        if type(node.min) == "number" and type(node.max) == "number" and node.min > node.max then
            logging.violate("storage.invalid_axis_type", "%s: int min cannot exceed max", prefix)
        end
        if node.width ~= nil and (type(node.width) ~= "number" or node.width < 1 or node.width > 32 or not IsInteger(node.width)) then
            logging.violate("storage.invalid_axis_type", "%s: int width must be a positive integer no greater than 32", prefix)
        elseif node.width ~= nil and node.offset == nil and (node.min == nil or node.max == nil) then
            logging.violate("storage.invalid_axis_type", "%s: int width requires min and max", prefix)
        elseif node.width ~= nil and node.offset == nil and node.min ~= nil and node.max ~= nil then
            local range = node.max - node.min
            local maxEncoded = range <= 0 and 0 or range
            local mask = bit32.rshift(0xFFFFFFFF, 32 - node.width)
            if maxEncoded > mask then
                logging.violate("storage.invalid_axis_type", "%s: int width cannot encode min/max range", prefix)
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
    isHashTokenValid = function(_, str)
        return type(str) == "string" and string.match(str, "^-?%d+$") ~= nil
    end,
    packWidth = function(node)
        return node and node._packWidth or nil
    end,
}

StorageTypes.string = {
    valueKind = "string",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "string" then
            logging.violate("storage.invalid_default", "%s: string default must be string, got %s", prefix, type(node.default))
        end
        if node.maxLen ~= nil and (type(node.maxLen) ~= "number" or node.maxLen < 1) then
            logging.violate("storage.invalid_axis_type", "%s: string maxLen must be a positive number", prefix)
        end
        node._maxLen = math.floor(tonumber(node.maxLen) or 256)
        if node._maxLen < 1 then node._maxLen = 256 end
        if node.default ~= nil and #node.default > node._maxLen then
            logging.violate(
                "storage.invalid_default",
                "%s: string default length must not exceed maxLen %d",
                prefix,
                node._maxLen
            )
        end
    end,
    normalize = function(node, value)
        return NormalizeString(node, value)
    end,
    toHash = function(node, value)
        return NormalizeString(node, value)
    end,
    fromHash = function(node, str)
        return NormalizeString(node, str)
    end,
    isHashTokenValid = function(_, str)
        return str ~= nil
    end,
}

StorageTypes.packedInt = {
    valueKind = "int",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "number" then
            logging.violate("storage.invalid_default", "%s: packedInt default must be number, got %s", prefix, type(node.default))
        elseif node.default ~= nil and not IsInteger(node.default) then
            logging.violate("storage.invalid_default", "%s: packedInt default must be an integer", prefix)
        end
        if node.width == nil then
            logging.violate("storage.invalid_axis_type", "%s: packedInt width is required", prefix)
        elseif type(node.width) ~= "number" or node.width < 1 or node.width > 32 or not IsInteger(node.width) then
            logging.violate("storage.invalid_axis_type", "%s: packedInt width must be a positive number no greater than 32", prefix)
        end
        if type(node.bits) ~= "table" or #node.bits == 0 then
            logging.violate("storage.invalid_schema", "%s: packedInt bits must be a non-empty list", prefix)
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
    isHashTokenValid = function(_, str)
        return type(str) == "string" and string.match(str, "^-?%d+$") ~= nil
    end,
    packWidth = function(node)
        return node and node._packWidth or nil
    end,
}

StorageTypes.table = {
    valueKind = "table",
    validate = function(node, prefix)
        if node.default ~= nil and node._tableDefaultPrepared ~= true then
            logging.violate("storage.invalid_default", "%s: table roots do not support default; use defaultRows", prefix)
        end
        if node.minRows ~= nil and (type(node.minRows) ~= "number" or node.minRows < 0) then
            logging.violate("storage.invalid_axis_type", "%s: table minRows must be a non-negative number", prefix)
        end
        if node.maxRows ~= nil and (type(node.maxRows) ~= "number" or node.maxRows < 0) then
            logging.violate("storage.invalid_axis_type", "%s: table maxRows must be a non-negative number", prefix)
        end
        if node.defaultRows ~= nil and (type(node.defaultRows) ~= "number" or node.defaultRows < 0) then
            logging.violate("storage.invalid_axis_type", "%s: table defaultRows must be a non-negative number", prefix)
        end
        if type(node.minRows) == "number" and type(node.maxRows) == "number" and node.minRows > node.maxRows then
            logging.violate("storage.invalid_axis_type", "%s: table minRows cannot exceed maxRows", prefix)
        end
        if type(node.row) ~= "table" or #node.row == 0 then
            logging.violate("storage.invalid_table_row", "%s: table row must be a non-empty storage schema", prefix)
        end
    end,
    normalize = function(node, value)
        return storage.table.NormalizeTableValue(node, value)
    end,
    equals = function(node, a, b)
        return values.deepEqual(
            storage.table.NormalizeTableValue(node, a),
            storage.table.NormalizeTableValue(node, b)
        )
    end,
    toHash = function(node, value)
        return storage.table.SerializeTableValue(node, value)
    end,
    fromHash = function(node, str)
        return storage.table.DeserializeTableValue(node, str)
    end,
    isHashTokenValid = function(node, str)
        return storage.table.IsSerializedTableValue(node, str)
    end,
}

return {
    types = StorageTypes,
    IsInteger = IsInteger,
    NormalizeInteger = NormalizeInteger,
}
