local deps = ...

local logging = deps.logging
local storageInternal = deps.storage
local values = deps.values
local ClonePersistedValue = values.deepCopy
local NormalizeStorageValue = storageInternal.NormalizeStorageValue
local DecodePackedChild = storageInternal.packed.DecodePackedChild

---Staged UI-owned data over committed roots.
---Returns the view handed to UI facades/controls and the transaction internals
---handed only to the module-state transaction.
---@param storageConfig table
---@param storage table Prepared storage.
---@param committed AdamantModpackLib.CommittedRoots
---@return AdamantModpackLib.StagedState view
---@return AdamantModpackLib.StagedTxnInternals internals
local function create(storageConfig, storage, committed)
    local stagedRootNodes = storageInternal.getStagedRoots(storage)
    local aliasNodes = storageInternal.getAliases(storage)
    local staging = {}
    local dirty = false
    local dirtyRoots = {}
    local configEntries = {}
    local tableHandles = {}
    local fieldHandles = {}

    for _, root in ipairs(stagedRootNodes) do
        if root._persist then
            configEntries[root.alias] = storageConfig.getEntry(root._storageKey)
        end
    end

    local function readPersistedConfigValue(root)
        if not root._persist then
            return nil
        end
        local entry = configEntries[root.alias]
        if entry then
            return entry:get()
        end
        return storageConfig.readValue(root._storageKey, root)
    end

    local function readConfigValue(root)
        if not root._persist then
            if root._mode == "runtime" then
                return committed.peekRoot(root)
            end
            return nil
        end
        local committedValue = committed.peekRoot(root)
        if committedValue ~= nil then
            return committedValue
        end
        return readPersistedConfigValue(root)
    end

    local function writeConfigValue(root, value)
        if not root._persist then
            return
        end
        storageConfig.writeValue(root._storageKey, value, root)
        committed.replaceRoot(root, value)
    end

    local function syncPackedChildren(root, packedValue)
        for _, child in ipairs(root._bitAliases) do
            staging[child.alias] = DecodePackedChild(child, packedValue)
        end
    end

    local function writeRootToStaging(root, value)
        local normalized = NormalizeStorageValue(root, value)
        local current = staging[root.alias]
        if storageInternal.valuesEqual(root, current, normalized) then
            return false
        end
        staging[root.alias] = normalized
        if root.type == "packedInt" then
            syncPackedChildren(root, normalized)
        end
        if root._persist then
            dirtyRoots[root.alias] = true
            dirty = true
        end
        return true
    end

    local function loadRootIntoStaging(root)
        local value = readConfigValue(root)
        if value == nil then
            value = ClonePersistedValue(root.default)
        end
        local normalized = NormalizeStorageValue(root, value)
        staging[root.alias] = normalized
        if root.type == "packedInt" then
            syncPackedChildren(root, normalized)
        end
    end

    local function readStagedRoot(root)
        if staging[root.alias] == nil then
            loadRootIntoStaging(root)
        end
        return staging[root.alias]
    end

    local function clearDirty()
        dirty = false
        dirtyRoots = {}
    end

    local function copyConfigToStaging()
        for _, root in ipairs(stagedRootNodes) do
            loadRootIntoStaging(root)
        end
        clearDirty()
    end

    local function flushToConfig()
        for _, root in ipairs(stagedRootNodes) do
            if dirtyRoots[root.alias] then
                writeConfigValue(root, staging[root.alias])
            end
        end
        clearDirty()
    end

    local function captureDirtyConfigSnapshot()
        local snapshot = {}
        for _, root in ipairs(stagedRootNodes) do
            if dirtyRoots[root.alias] then
                table.insert(snapshot, {
                    root = root,
                    value = ClonePersistedValue(readConfigValue(root)),
                })
            end
        end
        return snapshot
    end

    local function restoreConfigSnapshot(snapshot)
        for _, entry in ipairs(snapshot or {}) do
            writeConfigValue(entry.root, ClonePersistedValue(entry.value))
        end
    end

    -- Data-only surface: status aliases belong to status_state.
    local function resolveDataNode(alias, context)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("staged_state.unknown_alias", "%s: unknown alias '%s'", context, tostring(alias))
            return nil
        end
        if node._mode == "runtime" then
            logging.violate("staged_state.invalid_surface", "%s: alias '%s' is status, not data storage",
                context, tostring(alias))
            return nil
        end
        return node
    end

    local readBackend = {
        readRoot = function(root)
            return staging[root.alias]
        end,
        canRead = function(_, alias)
            return resolveDataNode(alias, "stagedState.read") ~= nil
        end,
        onUnknownRead = function(alias)
            logging.violate("staged_state.unknown_alias", "stagedState.read: unknown alias '%s'", tostring(alias))
        end,
    }

    local writeBackend = {
        readRoot = readStagedRoot,
        canWrite = function(_, alias)
            return resolveDataNode(alias, "stagedState.write") ~= nil
        end,
        writeRoot = writeRootToStaging,
        writeAliasValue = function(node, aliasValue)
            staging[node.alias] = aliasValue
        end,
        onUnknownWrite = function(alias)
            logging.violate("staged_state.unknown_alias", "stagedState.write: unknown alias '%s'", tostring(alias))
        end,
    }

    local function readStagingValue(alias)
        return storageInternal.readAlias(aliasNodes, readBackend, alias)
    end

    local function writeStagingValue(alias, value)
        storageInternal.writeAlias(aliasNodes, writeBackend, alias, value)
    end

    local function resetAliasValue(alias)
        local node = aliasNodes[alias]
        if not node then
            logging.violate("staged_state.unknown_alias", "stagedState.reset: unknown alias '%s'", tostring(alias))
            return
        end
        writeStagingValue(alias, ClonePersistedValue(node.default))
    end

    local function getTableHandleForNode(alias, node)
        local cached = tableHandles[alias]
        if cached then
            return cached
        end
        local handle = storageInternal.table.CreateTableHandle(node, {
            readRoot = readStagedRoot,
            writeRoot = writeRootToStaging,
            normalizedRoot = true,
        })
        tableHandles[alias] = handle
        return handle
    end

    local view = {}

    local function getFieldHandleForNode(alias, node)
        local cached = fieldHandles[alias]
        if cached then
            return cached
        end
        local field = storageInternal.field.create(view, alias, node, "stagedState.get")
        fieldHandles[alias] = field
        return field
    end

    function view.get(alias, context)
        local node = resolveDataNode(alias, context or "stagedState.get")
        if not node then
            return nil
        end
        if node.type == "table" and not node._isBitAlias then
            return getTableHandleForNode(alias, node)
        end
        return getFieldHandleForNode(alias, node)
    end

    view.read = readStagingValue
    view.write = writeStagingValue
    view.reset = resetAliasValue

    function view.table(alias)
        local node = resolveDataNode(alias, "stagedState.table")
        if not node then
            return nil
        end
        if node.type ~= "table" or node._isBitAlias then
            logging.violate("staged_state.invalid_table_alias", "stagedState.table: alias '%s' is not table storage",
                tostring(alias))
            return nil
        end
        return getTableHandleForNode(alias, node)
    end

    function view.getAliasSchema(alias)
        return aliasNodes[alias]
    end

    copyConfigToStaging()

    local internals = {}

    function internals.isDirty()
        return dirty
    end

    internals.flushToConfig = flushToConfig
    internals.syncFromCommitted = copyConfigToStaging
    internals.captureDirtyConfigSnapshot = captureDirtyConfigSnapshot
    internals.restoreConfigSnapshot = restoreConfigSnapshot

    function internals.reloadFromConfig()
        local receipt = committed.reload()
        copyConfigToStaging()
        return receipt
    end

    ---@param exclude table<string, boolean> Root aliases to skip (validated by the txn).
    function internals.resetAll(exclude)
        local count = 0
        for _, root in ipairs(stagedRootNodes) do
            local alias = root.alias
            if root._mode ~= "runtime" and not exclude[alias]
                and not storageInternal.valuesEqual(root, readStagingValue(alias), root.default) then
                resetAliasValue(alias)
                count = count + 1
            end
        end
        return count > 0, count
    end

    function internals.auditMismatches()
        storageConfig.reloadSource()
        local mismatches = {}
        for _, root in ipairs(stagedRootNodes) do
            if root._persist and root._mode ~= "runtime" then
                local persistedValue = readPersistedConfigValue(root)
                if persistedValue == nil then
                    persistedValue = ClonePersistedValue(root.default)
                end
                persistedValue = NormalizeStorageValue(root, persistedValue)
                if not storageInternal.valuesEqual(root, persistedValue, staging[root.alias]) then
                    table.insert(mismatches, root.alias)
                end
                if root.type == "packedInt" then
                    for _, child in ipairs(root._bitAliases) do
                        local childValue = DecodePackedChild(child, persistedValue)
                        if not storageInternal.valuesEqual(child, childValue, staging[child.alias]) then
                            table.insert(mismatches, child.alias)
                        end
                    end
                end
            end
        end
        return mismatches
    end

    return view, internals
end

return {
    create = create,
}
