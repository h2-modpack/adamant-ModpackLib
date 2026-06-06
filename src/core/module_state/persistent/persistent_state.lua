local deps = ...

local logging = deps.logging
local storageInternal = deps.storage
local values = deps.values
local ClonePersistedValue = values.deepCopy
local NormalizeStorageValue = storageInternal.NormalizeStorageValue

local function create(storageConfig, storage)
    local persistentState = {}

    local persistRoots = storageInternal.getPersistRoots(storage)
    local allRoots = storageInternal.getStagedRoots(storage)
    local aliasNodes = storageInternal.getAliases(storage)
    local committedRoots = {}
    local tableHandles = {}
    local statusTableHandles = {}
    local fieldHandles = {}
    local statusFieldHandles = {}
    local readRootNode

    local function readRaw(alias)
        return storageConfig.readValue(alias)
    end

    local function writeRaw(alias, value)
        storageConfig.writeValue(alias, value)
    end

    local function readNormalizedRoot(root)
        local raw = readRaw(root._storageKey)
        local source = raw
        if source == nil then
            source = ClonePersistedValue(root.default)
        end
        return NormalizeStorageValue(root, source), raw
    end

    local function usesCommittedRoot(root)
        return root and (root._persist or root._mode == "runtime")
    end

    local function replaceCommittedRoot(root, value)
        if not usesCommittedRoot(root) then
            return
        end
        committedRoots[root.alias] = ClonePersistedValue(NormalizeStorageValue(root, value))
    end

    local function writeCommittedRoot(root, value)
        if not usesCommittedRoot(root) then
            return false
        end
        local normalized = NormalizeStorageValue(root, value)
        local current = readRootNode(root)
        if storageInternal.valuesEqual(root, current, normalized) then
            return false
        end
        committedRoots[root.alias] = ClonePersistedValue(normalized)
        if root._persist then
            writeRaw(root._storageKey, normalized)
        end
        return true
    end

    readRootNode = function(root)
        if usesCommittedRoot(root) then
            local value = committedRoots[root.alias]
            if value ~= nil then
                return value
            end
        end
        return ClonePersistedValue(root.default)
    end

    local function hydratePersistRoot(root)
        if not root._persist then
            return
        end

        local normalized, raw = readNormalizedRoot(root)
        replaceCommittedRoot(root, normalized)
        if raw ~= nil and values.deepEqual(raw, normalized) then
            return
        end

        if raw == nil and storageConfig.ensureValue(root._storageKey, normalized) then
            return
        end
        writeRaw(root._storageKey, normalized)
    end

    local function hydratePersistRoots()
        for _, root in ipairs(persistRoots) do
            hydratePersistRoot(root)
        end
        for _, root in ipairs(allRoots) do
            if root._mode == "runtime" and not root._persist and committedRoots[root.alias] == nil then
                replaceCommittedRoot(root, root.default)
            end
        end
    end

    hydratePersistRoots()

    function persistentState._replaceRoot(root, value)
        replaceCommittedRoot(root, value)
    end

    function persistentState._reloadFromConfig()
        hydratePersistRoots()
    end

    function persistentState._readRoot(root)
        if not usesCommittedRoot(root) then
            return nil
        end
        return committedRoots[root.alias]
    end

    local storeReadBackend = {
        readRoot = readRootNode,
        canRead = function(node, alias)
            if node._mode == "runtime" then
                logging.violate(
                    "store.invalid_surface",
                    "persistentState.read: alias '%s' is status; use persistentState.status.read",
                    tostring(alias))
                return false
            end
            if not node._persist then
                logging.violate(
                    "store.invalid_surface",
                    "store.read: alias '%s' is staged-only; use draw state for UI-only state",
                    tostring(alias))
                return false
            end
            return true
        end,
        onUnknownRead = function(alias)
            logging.violate("store.unknown_alias", "store.read: unknown storage alias '%s'", tostring(alias))
        end,
    }

    local function getStatusNode(alias, context, allowBitAlias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("status.unknown_alias", "%s: unknown status alias '%s'", context, tostring(alias))
            return nil
        end
        if node._mode ~= "runtime" then
            logging.violate("status.invalid_surface", "%s: alias '%s' is not status storage",
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

    local statusWriteBackend = {
        readRoot = readRootNode,
        canWrite = function(_, alias)
            return getStatusNode(alias, "persistentState.status.write", true) ~= nil
        end,
        writeRoot = writeCommittedRoot,
        onUnknownWrite = function(alias)
            logging.violate("status.unknown_alias", "persistentState.status.write: unknown status alias '%s'",
                tostring(alias))
        end,
    }

    local function writeStatusValue(alias, value)
        local node = getStatusNode(alias, "persistentState.status.write", true)
        if not node then
            return false
        end
        if node.type == "table" and not node._isBitAlias then
            logging.violate("status.invalid_surface",
                "persistentState.status.write: alias '%s' is table storage; use a table handle or table cell write",
                tostring(alias))
            return false
        end
        return storageInternal.writeAlias(aliasNodes, statusWriteBackend, alias, value)
    end

    local function resetStatusRoot(alias)
        local node = getStatusNode(alias, "persistentState.status.reset")
        if not node then
            return false
        end
        return writeCommittedRoot(node, node.default)
    end

    local function resetStatusValue(alias)
        local node = getStatusNode(alias, "persistentState.status.reset", true)
        if not node then
            return false
        end
        if node._isBitAlias then
            return writeStatusValue(alias, node.default)
        end
        return resetStatusRoot(alias)
    end

    local function countResettableStatusRoots(opts)
        local exclude = type(opts) == "table" and type(opts.exclude) == "table" and opts.exclude or {}
        local count = 0

        for _, root in ipairs(allRoots) do
            local alias = root.alias
            if root._mode == "runtime" and alias ~= nil and not exclude[alias] then
                local current = readRootNode(root)
                if not storageInternal.valuesEqual(root, current, root.default) then
                    count = count + 1
                end
            end
        end

        return count > 0, count
    end

    local function resetAllStatusRoots(opts)
        local exclude = type(opts) == "table" and type(opts.exclude) == "table" and opts.exclude or {}
        local count = 0

        for _, root in ipairs(allRoots) do
            local alias = root.alias
            if root._mode == "runtime" and alias ~= nil and not exclude[alias] then
                local current = readRootNode(root)
                if not storageInternal.valuesEqual(root, current, root.default) and resetStatusRoot(alias) then
                    count = count + 1
                end
            end
        end

        return count > 0, count
    end

    function persistentState.read(alias)
        return storageInternal.readAlias(aliasNodes, storeReadBackend, alias)
    end

    function persistentState.getAliasSchema(alias)
        return aliasNodes[alias]
    end

    local statusReadBackend = {
        readRoot = readRootNode,
        canRead = function(_, alias)
            return getStatusNode(alias, "persistentState.status.read", true) ~= nil
        end,
        onUnknownRead = function(alias)
            logging.violate("status.unknown_alias", "persistentState.status.read: unknown status alias '%s'",
                tostring(alias))
        end,
    }

    local getTableHandleForNode
    local getStatusTableHandleForNode
    local getFieldHandleForNode

    local statusFieldOwner = {
        read = function(alias)
            local node = getStatusNode(alias, "persistentState.status.read", true)
            if not node then
                return nil
            end
            return storageInternal.readAlias(aliasNodes, statusReadBackend, alias)
        end,
        write = writeStatusValue,
        reset = resetStatusValue,
        getAliasSchema = function(alias)
            return aliasNodes[alias]
        end,
    }

    local function getStatusFieldHandleForNode(alias, node)
        local cached = statusFieldHandles[alias]
        if cached then
            return cached
        end

        local field = storageInternal.field.createKnown(statusFieldOwner, alias, node, "persistentState.status.get")
        statusFieldHandles[alias] = field
        return field
    end

    local function getStatusDataObject(alias)
        local node = getStatusNode(alias, "persistentState.status.get", true)
        if not node then
            return nil
        end
        if node.type == "table" and not node._isBitAlias then
            return getStatusTableHandleForNode(alias, node)
        end
        return getStatusFieldHandleForNode(alias, node)
    end

    persistentState.status = {
        read = function(alias, ...)
            local ref = getStatusDataObject(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
        get = getStatusDataObject,
        table = function(alias)
            local node = getStatusNode(alias, "persistentState.status.table", true)
            if not node then
                return nil
            end
            if node.type ~= "table" or node._isBitAlias then
                logging.violate("status.invalid_table_alias",
                    "persistentState.status.table: alias '%s' is not table storage", tostring(alias))
                return nil
            end
            return getStatusTableHandleForNode(alias, node)
        end,
        write = function(alias, ...)
            local argc = select("#", ...)
            if argc == 1 then
                return writeStatusValue(alias, ...)
            end
            local ref = getStatusDataObject(alias)
            if ref == nil then
                return nil
            end
            if type(ref.write) ~= "function" then
                logging.violate("status.invalid_surface", "persistentState.status.write: alias '%s' is not writable",
                    tostring(alias))
                return nil
            end
            return ref:write(...)
        end,
        reset = function(alias, ...)
            local argc = select("#", ...)
            if argc == 0 then
                return resetStatusValue(alias)
            end
            local ref = getStatusDataObject(alias)
            if ref == nil then
                return nil
            end
            if type(ref.reset) ~= "function" then
                logging.violate("status.invalid_surface", "persistentState.status.reset: alias '%s' is not resettable",
                    tostring(alias))
                return nil
            end
            return ref:reset(...)
        end,
        countResettable = countResettableStatusRoots,
        resetAll = resetAllStatusRoots,
    }

    getTableHandleForNode = function(alias, node)
        local cached = tableHandles[alias]
        if cached then
            return cached
        end

        local handle = storageInternal.table.CreateTableHandle(node, {
            readRoot = readRootNode,
            normalizedRoot = true,
        })
        tableHandles[alias] = handle
        return handle
    end

    getStatusTableHandleForNode = function(alias, node)
        local cached = statusTableHandles[alias]
        if cached then
            return cached
        end

        local handle = storageInternal.table.CreateTableHandle(node, {
            readRoot = readRootNode,
            writeRoot = writeCommittedRoot,
            normalizedRoot = true,
        })
        statusTableHandles[alias] = handle
        return handle
    end

    getFieldHandleForNode = function(alias, node)
        local cached = fieldHandles[alias]
        if cached then
            return cached
        end

        local field = storageInternal.field.createKnown(persistentState, alias, node, "store.get")
        fieldHandles[alias] = field
        return field
    end

    function persistentState.table(alias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("store.unknown_alias", "store.table: unknown storage alias '%s'", tostring(alias))
            return nil
        end
        if node.type ~= "table" or node._isBitAlias then
            logging.violate("store.invalid_table_alias", "store.table: alias '%s' is not table storage", tostring(alias))
            return nil
        end
        if node._mode == "runtime" then
            logging.violate("store.invalid_surface",
                "persistentState.table: alias '%s' is status; use persistentState.status.table", tostring(alias))
            return nil
        end
        if not node._persist then
            logging.violate("store.invalid_surface", "store.table: alias '%s' is staged-only; use stagedState.table()",
                tostring(alias))
            return nil
        end
        return getTableHandleForNode(alias, node)
    end

    function persistentState.get(alias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("store.unknown_alias", "store.get: unknown storage alias '%s'", tostring(alias))
            return nil
        end
        if node._mode == "runtime" then
            logging.violate(
                "store.invalid_surface",
                "persistentState.get: alias '%s' is status; use persistentState.status.get",
                tostring(alias))
            return nil
        end
        if not node._persist then
            logging.violate(
                "store.invalid_surface",
                "store.get: alias '%s' is staged-only; use draw state for UI-only state",
                tostring(alias))
            return nil
        end
        if node.type == "table" and not node._isBitAlias then
            return getTableHandleForNode(alias, node)
        end
        return getFieldHandleForNode(alias, node)
    end

    return persistentState
end

return {
    create = create,
}
