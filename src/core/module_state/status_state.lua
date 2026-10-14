local deps = ...

local logging = deps.logging
local storageInternal = deps.storage

---Runtime-authored status storage over committed roots.
---@param committed AdamantModpackLib.CommittedRoots
---@return AdamantModpackLib.StatusState
local function create(committed)
    local aliasNodes = committed.aliasNodes
    local allRoots = committed.allRoots
    local readRoot = committed.readRoot
    local writeRoot = committed.writeRoot
    local tableHandles = {}
    local fieldHandles = {}
    local status = {}

    local function resolveStatusNode(alias, context, allowBitAlias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("status.unknown_alias", "%s: unknown status alias '%s'", context, tostring(alias))
            return nil
        end
        if node._mode ~= "runtime" then
            logging.violate("status.invalid_surface", "%s: alias '%s' is data storage, not status",
                context, tostring(alias))
            return nil
        end
        if node._isBitAlias and allowBitAlias ~= true then
            logging.violate("status.invalid_surface", "%s: alias '%s' is a packed child; set the status root instead",
                context, tostring(alias))
            return nil
        end
        return node
    end

    local readBackend = {
        readRoot = readRoot,
        canRead = function(_, alias)
            return resolveStatusNode(alias, "status.read", true) ~= nil
        end,
        onUnknownRead = function(alias)
            logging.violate("status.unknown_alias", "status.read: unknown status alias '%s'", tostring(alias))
        end,
    }

    local writeBackend = {
        readRoot = readRoot,
        canWrite = function(_, alias)
            return resolveStatusNode(alias, "status.write", true) ~= nil
        end,
        writeRoot = writeRoot,
        onUnknownWrite = function(alias)
            logging.violate("status.unknown_alias", "status.write: unknown status alias '%s'", tostring(alias))
        end,
    }

    local function writeValue(alias, value)
        local node = resolveStatusNode(alias, "status.write", true)
        if not node then
            return false
        end
        if node.type == "table" and not node._isBitAlias then
            logging.violate("status.invalid_surface",
                "status.write: alias '%s' is table storage; use a table handle or table cell write",
                tostring(alias))
            return false
        end
        return storageInternal.writeAlias(aliasNodes, writeBackend, alias, value)
    end

    local function resetValue(alias)
        local node = resolveStatusNode(alias, "status.reset", true)
        if not node then
            return false
        end
        if node._isBitAlias then
            return writeValue(alias, node.default)
        end
        return writeRoot(node, node.default)
    end

    local fieldOwner = {
        read = function(alias)
            return storageInternal.readAlias(aliasNodes, readBackend, alias)
        end,
        write = writeValue,
        reset = resetValue,
        getAliasSchema = function(alias)
            return aliasNodes[alias]
        end,
    }

    local function getTableHandleForNode(alias, node)
        local cached = tableHandles[alias]
        if cached then
            return cached
        end
        local handle = storageInternal.table.CreateTableHandle(node, {
            readRoot = readRoot,
            writeRoot = writeRoot,
            normalizedRoot = true,
        })
        tableHandles[alias] = handle
        return handle
    end

    local function getFieldHandleForNode(alias, node)
        local cached = fieldHandles[alias]
        if cached then
            return cached
        end
        local field = storageInternal.field.create(fieldOwner, alias, node, "status.get")
        fieldHandles[alias] = field
        return field
    end

    function status.get(alias, context)
        local node = resolveStatusNode(alias, context or "status.get", true)
        if not node then
            return nil
        end
        if node.type == "table" and not node._isBitAlias then
            return getTableHandleForNode(alias, node)
        end
        return getFieldHandleForNode(alias, node)
    end

    function status.read(alias, ...)
        local ref = status.get(alias, "status.read")
        if ref == nil then
            return nil
        end
        return ref:read(...)
    end

    function status.table(alias)
        local node = resolveStatusNode(alias, "status.table", true)
        if not node then
            return nil
        end
        if node.type ~= "table" or node._isBitAlias then
            logging.violate("status.invalid_table_alias", "status.table: alias '%s' is not table storage",
                tostring(alias))
            return nil
        end
        return getTableHandleForNode(alias, node)
    end

    function status.write(alias, ...)
        if select("#", ...) == 1 then
            return writeValue(alias, ...)
        end
        local ref = status.get(alias, "status.write")
        if ref == nil then
            return nil
        end
        return ref:write(...)
    end

    function status.reset(alias, ...)
        if select("#", ...) == 0 then
            return resetValue(alias)
        end
        local ref = status.get(alias, "status.reset")
        if ref == nil then
            return nil
        end
        return ref:reset(...)
    end

    -- `exclude` is the root-alias skip set resolved from ResetOpts by the module-state txn.
    local function eachResettableRoot(exclude, visit)
        local count = 0
        for _, root in ipairs(allRoots) do
            if root._mode == "runtime" and not exclude[root.alias]
                and not storageInternal.valuesEqual(root, readRoot(root), root.default)
                and visit(root) then
                count = count + 1
            end
        end
        return count > 0, count
    end

    function status.countResettable(exclude)
        return eachResettableRoot(exclude, function()
            return true
        end)
    end

    function status.resetAll(exclude)
        return eachResettableRoot(exclude, function(root)
            return writeRoot(root, root.default)
        end)
    end

    return status
end

return {
    create = create,
}
