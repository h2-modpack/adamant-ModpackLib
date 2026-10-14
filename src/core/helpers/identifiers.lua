-- Stable identifier rules shared by definition, storage, controls, and status contact points.
local identifiers = {}

local StablePattern = "^[A-Za-z][A-Za-z0-9_]*$"
local InternalPathSeparator = "-"

identifiers.STABLE_DESCRIPTION = "must start with a letter and contain only letters, digits, and underscores"
identifiers.INTERNAL_DESCRIPTION = "must start with '_' and contain '-'-separated stable identifier segments"

---@param value any
---@return boolean
function identifiers.isStable(value)
    return type(value) == "string" and string.match(value, StablePattern) ~= nil
end

---Lib-generated identifier: `_` followed by `-`-separated stable identifier segments.
---@param value any
---@return boolean
function identifiers.isInternal(value)
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
        if not identifiers.isStable(segment) then
            return false
        end
        if separatorStart == nil then
            return true
        end
        segmentStart = separatorEnd + 1
    end
end

return identifiers
