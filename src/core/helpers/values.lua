local values = {}

function values.deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[values.deepCopy(key, seen)] = values.deepCopy(child, seen)
    end
    return copy
end

function values.deepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end

    seen = seen or {}
    local seenForA = seen[a]
    if seenForA and seenForA[b] then
        return true
    end
    if not seenForA then
        seenForA = {}
        seen[a] = seenForA
    end
    seenForA[b] = true

    for key, value in pairs(a) do
        if not values.deepEqual(value, b[key], seen) then
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

return values
