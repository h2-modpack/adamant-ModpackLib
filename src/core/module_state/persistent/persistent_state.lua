local deps = ...

local logging = deps.logging
local storageInternal = deps.storage
local values = deps.values
local ClonePersistedValue = values.deepCopy
local NormalizeStorageValue = storageInternal.NormalizeStorageValue

---@param storageConfig table
---@param storage table Prepared storage.
---@return AdamantModpackLib.PersistentState persistentState
---@return AdamantModpackLib.CommittedRoots committed
local function create(storageConfig, storage)
    local persistentState = {}

    local persistRoots = storageInternal.getPersistRoots(storage)
    local allRoots = storageInternal.getStagedRoots(storage)
    local aliasNodes = storageInternal.getAliases(storage)
    local committedRoots = {}
    local tableHandles = {}
    local fieldHandles = {}
    local readRootNode

    local function readRaw(root)
        return storageConfig.readValue(root._storageKey, root)
    end

    local function writeRaw(root, value)
        storageConfig.writeValue(root._storageKey, value, root)
    end

    local function readNormalizedRoot(root)
        local raw = readRaw(root)
        local source = raw
        if source == nil then
            source = ClonePersistedValue(root.default)
        end
        return NormalizeStorageValue(root, source), raw
    end

    local function isHydratedValueCurrent(root, raw, normalized)
        if values.deepEqual(raw, normalized) then
            return true
        end
        if root.type ~= "table" or type(raw) ~= "table" or getmetatable(raw) == nil then
            return false
        end
        if #raw ~= #normalized then
            return false
        end
        return storageInternal.valuesEqual(root, raw, normalized)
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
            writeRaw(root, normalized)
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

    local function peekCommittedRoot(root)
        if not usesCommittedRoot(root) then
            return nil
        end
        return committedRoots[root.alias]
    end

    local function hydratePersistRoot(root)
        if not root._persist then
            return
        end

        local normalized, raw = readNormalizedRoot(root)
        if raw == nil and storageConfig.ensureValue(root._storageKey, normalized, root) then
            raw = readRaw(root)
            if raw == nil then
                replaceCommittedRoot(root, normalized)
                return
            end
            normalized = NormalizeStorageValue(root, raw)
        end

        replaceCommittedRoot(root, normalized)
        if raw ~= nil and isHydratedValueCurrent(root, raw, normalized) then
            return
        end

        writeRaw(root, normalized)
    end

    local function hydratePersistRootsNow()
        for _, root in ipairs(persistRoots) do
            hydratePersistRoot(root)
        end
        for _, root in ipairs(allRoots) do
            if root._mode == "runtime" and not root._persist and committedRoots[root.alias] == nil then
                replaceCommittedRoot(root, root.default)
            end
        end
    end

    local function hydratePersistRoots()
        if type(storageConfig.withSaveBatch) == "function" then
            storageConfig.withSaveBatch(hydratePersistRootsNow)
            return
        end
        hydratePersistRootsNow()
    end

    local function capturePersistedRoots()
        local snapshot = {}
        for _, root in ipairs(persistRoots) do
            snapshot[root.alias] = ClonePersistedValue(readRootNode(root))
        end
        return snapshot
    end

    local function makeReloadReceipt(previous)
        local hadCommittedChanges = false
        local hadSettingChanges = false
        local hadStatusChanges = false
        for _, root in ipairs(persistRoots) do
            if not storageInternal.valuesEqual(root, previous[root.alias], readRootNode(root)) then
                hadCommittedChanges = true
                if root._mode == "runtime" then
                    hadStatusChanges = true
                else
                    hadSettingChanges = true
                end
            end
        end
        return {
            hadCommittedChanges = hadCommittedChanges,
            hadSettingChanges = hadSettingChanges,
            hadStatusChanges = hadStatusChanges,
        }
    end

    local function reloadCommittedRoots()
        local previous = capturePersistedRoots()
        hydratePersistRoots()
        return makeReloadReceipt(previous)
    end

    hydratePersistRoots()

    -- Data-only surface: status roots belong to status_state, transient roots to staged state.
    local function resolveDataNode(alias, context)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("store.unknown_alias", "%s: unknown storage alias '%s'", context, tostring(alias))
            return nil
        end
        if node._mode == "runtime" then
            logging.violate("store.invalid_surface", "%s: alias '%s' is status, not data storage",
                context, tostring(alias))
            return nil
        end
        if not node._persist then
            logging.violate("store.invalid_surface", "%s: alias '%s' is staged-only; use draw state for UI-only state",
                context, tostring(alias))
            return nil
        end
        return node
    end

    local storeReadBackend = {
        readRoot = readRootNode,
        canRead = function(_, alias)
            return resolveDataNode(alias, "store.read") ~= nil
        end,
        onUnknownRead = function(alias)
            logging.violate("store.unknown_alias", "store.read: unknown storage alias '%s'", tostring(alias))
        end,
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

    function persistentState.read(alias)
        return storageInternal.readAlias(aliasNodes, storeReadBackend, alias)
    end

    function persistentState.getAliasSchema(alias)
        return aliasNodes[alias]
    end

    function persistentState.table(alias)
        local node = resolveDataNode(alias, "store.table")
        if not node then
            return nil
        end
        if node.type ~= "table" or node._isBitAlias then
            logging.violate("store.invalid_table_alias", "store.table: alias '%s' is not table storage", tostring(alias))
            return nil
        end
        return getTableHandleForNode(alias, node)
    end

    function persistentState.get(alias, context)
        local node = resolveDataNode(alias, context or "store.get")
        if not node then
            return nil
        end
        if node.type == "table" and not node._isBitAlias then
            return getTableHandleForNode(alias, node)
        end
        return getFieldHandleForNode(alias, node)
    end

    local committed = {
        aliasNodes = aliasNodes,
        allRoots = allRoots,
        readRoot = readRootNode,
        peekRoot = peekCommittedRoot,
        replaceRoot = replaceCommittedRoot,
        writeRoot = writeCommittedRoot,
        reload = reloadCommittedRoots,
    }

    return persistentState, committed
end

return {
    create = create,
}
