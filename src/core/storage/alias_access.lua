local deps = ...

local nodeOps = deps.nodeOps
local packed = deps.packed
local aliasAccess = {}

-- Backends are Lib-built: `readRoot` is required; `writeRoot` is required for writes;
-- `canRead`/`canWrite`/`onUnknownRead`/`onUnknownWrite`/`writeAliasValue` are optional hooks.

function aliasAccess.readAlias(aliasNodes, backend, alias)
    local node = type(alias) == "string" and aliasNodes[alias] or nil
    if not node then
        if backend.onUnknownRead ~= nil then
            backend.onUnknownRead(alias)
        end
        return nil
    end

    if backend.canRead ~= nil and backend.canRead(node, alias) == false then
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
        if backend.onUnknownWrite ~= nil then
            backend.onUnknownWrite(alias)
        end
        return false
    end

    if backend.canWrite ~= nil and backend.canWrite(node, alias) == false then
        return false
    end

    if node._isBitAlias then
        local parent = node.parent
        local currentPacked = backend.readRoot(parent)
        local normalized = nodeOps.normalize(node, value)
        local currentValue = packed.DecodePackedChild(node, currentPacked)
        if nodeOps.valuesEqual(node, currentValue, normalized) then
            return false
        end

        local nextPacked = packed.writePackedBits(currentPacked, node.offset, node.width,
            packed.encodeChild(node, normalized))
        if nodeOps.valuesEqual(parent, currentPacked, nextPacked) then
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
