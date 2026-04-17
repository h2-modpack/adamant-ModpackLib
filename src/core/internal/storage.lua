local internal = AdamantModpackLib_Internal
internal.storage = internal.storage or {}
local storage = internal.storage

local function StorageKey(key)
    if type(key) == "table" then
        return table.concat(key, ".")
    end
    return tostring(key)
end

storage.StorageKey = StorageKey

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

storage.NormalizeInteger = NormalizeInteger
