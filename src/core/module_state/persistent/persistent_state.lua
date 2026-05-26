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
    local fieldHandles = {}

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

    local function readRootNode(root)
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
            if not node._persist and node._mode ~= "runtime" then
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

    local function getRuntimeNode(alias, context, allowBitAlias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("store.unknown_alias", "%s: unknown storage alias '%s'", context, tostring(alias))
            return nil
        end
        if node._mode ~= "runtime" then
            logging.violate("store.invalid_surface", "%s: alias '%s' is not runtime-owned storage",
                context, tostring(alias))
            return nil
        end
        if node._isBitAlias and allowBitAlias ~= true then
            logging.violate("store.invalid_surface", "%s: alias '%s' is a packed child; set the runtime root instead",
                context, tostring(alias))
            return nil
        end
        return node
    end

    local function writeRuntimeRoot(alias, value)
        local node = getRuntimeNode(alias, "store.runtime.set")
        if not node then
            return false
        end
        local normalized = NormalizeStorageValue(node, value)
        replaceCommittedRoot(node, normalized)
        if node._persist then
            writeRaw(node._storageKey, normalized)
        end
        return true
    end

    local function clearRuntimeRoot(alias)
        local node = getRuntimeNode(alias, "store.runtime.clear")
        if not node then
            return false
        end
        local normalized = ClonePersistedValue(node.default)
        replaceCommittedRoot(node, normalized)
        if node._persist then
            writeRaw(node._storageKey, normalized)
        end
        return true
    end

    function persistentState.read(alias)
        return storageInternal.readAlias(aliasNodes, storeReadBackend, alias)
    end

    function persistentState.getAliasSchema(alias)
        return aliasNodes[alias]
    end

    persistentState.runtime = {
        read = function(alias)
            if not getRuntimeNode(alias, "store.runtime.read", true) then
                return nil
            end
            return persistentState.read(alias)
        end,
        set = writeRuntimeRoot,
        clear = clearRuntimeRoot,
    }

    local function getTableHandleForNode(alias, node)
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

    local function getFieldHandleForNode(alias, node)
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
        if not node._persist and node._mode ~= "runtime" then
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
        if not node._persist and node._mode ~= "runtime" then
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
