local deps = ...

local storage = deps.storage
local packed = deps.packed
local aliasAccess = {}

function aliasAccess.readAlias(aliasNodes, backend, alias)
    local node = type(alias) == "string" and aliasNodes[alias] or nil
    if not node then
        if backend and backend.onUnknownRead ~= nil then
            backend.onUnknownRead(alias)
        end
        return nil
    end

    if backend and backend.canRead ~= nil and backend.canRead(node, alias) == false then
        return nil
    end

    if node._isBitAlias then
        return packed.DecodePackedChild(node, backend.readRoot(node.parent))
    end
    return backend.readRoot(node)
end

function aliasAccess.writeAlias(aliasNodes, backend, alias, value)
    local node = type(alias) == "string" and aliasNodes[alias] or nil
    if not node then
        if backend and backend.onUnknownWrite ~= nil then
            backend.onUnknownWrite(alias)
        end
        return false
    end

    if backend and backend.canWrite ~= nil and backend.canWrite(node, alias) == false then
        return false
    end

    if node._isBitAlias then
        local parent = node.parent
        local currentPacked = backend.readRoot(parent)
        local normalized = storage.NormalizeStorageValue(node, value)
        local currentValue = packed.DecodePackedChild(node, currentPacked)
        if storage.valuesEqual(node, currentValue, normalized) then
            return false
        end

        local encoded = node.type == "bool" and (normalized and 1 or 0) or normalized
        local nextPacked = packed.writePackedBits(currentPacked, node.offset, node.width, encoded)
        if storage.valuesEqual(parent, currentPacked, nextPacked) then
            if backend.writeAliasValue ~= nil then
                backend.writeAliasValue(node, normalized)
            end
            return false
        end

        local changed = backend.writeRoot(parent, nextPacked)
        if backend.writeAliasValue ~= nil then
            backend.writeAliasValue(node, normalized)
        end
        return changed ~= false
    end

    return backend.writeRoot(node, value) ~= false
end

return aliasAccess
