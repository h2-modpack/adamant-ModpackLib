local deps = ...

local values = deps.values

-- Records original values of table keys before a plan first touches them, and restores them.
return function()
    local NIL = {}
    local savedValues = {}

    local function backup(tbl, ...)
        savedValues[tbl] = savedValues[tbl] or {}
        local saved = savedValues[tbl]
        for i = 1, select("#", ...) do
            local key = select(i, ...)
            if saved[key] == nil then
                local value = tbl[key]
                saved[key] = (value == nil) and NIL or values.deepCopy(value)
            end
        end
    end

    local function restore()
        for tbl, keys in pairs(savedValues) do
            for key, value in pairs(keys) do
                if value == NIL then
                    tbl[key] = nil
                elseif type(value) == "table" then
                    tbl[key] = values.deepCopy(value)
                else
                    tbl[key] = value
                end
            end
        end
        for tbl in pairs(savedValues) do
            savedValues[tbl] = nil
        end
    end

    return backup, restore
end
