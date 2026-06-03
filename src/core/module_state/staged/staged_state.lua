local deps = ...

local logging = deps.logging
local storageInternal = deps.storage
local values = deps.values
local ClonePersistedValue = values.deepCopy
local NormalizeStorageValue = storageInternal.NormalizeStorageValue
local DecodePackedChild = storageInternal.packed.DecodePackedChild

---@param storageConfig StorageConfigAdapter
---@param storage StorageSchema
---@param persistentState PersistentState|nil
---@return StagedState
local function createStagedState(storageConfig, storage, persistentState)
    local stagedRootNodes = storageInternal.getStagedRoots(storage)
    local aliasNodes = storageInternal.getAliases(storage)
    local staging = {}
    local dirty = false
    local dirtyRoots = {}
    local configEntries = {}
    local tableHandles = {}
    local fieldHandles = {}
    local runtimeOwnedFieldHandles = {}

    for _, root in ipairs(stagedRootNodes) do
        if root._persist then
            configEntries[root.alias] = storageConfig.getEntry(root._storageKey)
        end
    end

    local function readPersistedConfigValue(root)
        if not root._persist then
            return nil
        end
        local entry = configEntries and configEntries[root.alias] or nil
        if entry then
            return entry:get()
        end
        return storageConfig.readValue(root._storageKey)
    end

    local function readConfigValue(root)
        if not root._persist then
            if root._mode == "runtime" and persistentState and type(persistentState._readRoot) == "function" then
                return persistentState._readRoot(root)
            end
            return nil
        end
        if persistentState and type(persistentState._readRoot) == "function" then
            return persistentState._readRoot(root)
        end
        return readPersistedConfigValue(root)
    end

    local function writeConfigValue(root, value)
        if not root._persist then
            return
        end
        local entry = configEntries and configEntries[root.alias] or nil
        if entry then
            entry:set(value)
            if persistentState and type(persistentState._replaceRoot) == "function" then
                persistentState._replaceRoot(root, value)
            end
            return
        end
        storageConfig.writeValue(root._storageKey, value)
        if persistentState and type(persistentState._replaceRoot) == "function" then
            persistentState._replaceRoot(root, value)
        end
    end

    local function syncPackedChildren(root, packedValue)
        for _, child in ipairs(root._bitAliases or {}) do
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

    local function copyConfigToStaging()
        for _, root in ipairs(stagedRootNodes) do
            loadRootIntoStaging(root)
        end
    end

    local function copyStagingToConfig()
        for _, root in ipairs(stagedRootNodes) do
            if dirtyRoots[root.alias] then
                writeConfigValue(root, staging[root.alias])
            end
        end
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

    local function clearDirty()
        dirty = false
        dirtyRoots = {}
    end

    local stagedReadBackend = {
        readRoot = function(root)
            return staging[root.alias]
        end,
        canRead = function(node, alias)
            if node._mode == "runtime" then
                logging.violate(
                    "staged_state.invalid_surface",
                    "stagedState.read: alias '%s' is runtime-owned; use stagedState.runtimeOwned.read",
                    tostring(alias))
                return false
            end
            return true
        end,
        onUnknownRead = function(alias)
            logging.violate("staged_state.unknown_alias", "stagedState.read: unknown alias '%s'", tostring(alias))
        end,
    }

    local runtimeOwnedReadBackend = {
        readRoot = function(root)
            if persistentState and type(persistentState._readRoot) == "function" then
                return persistentState._readRoot(root)
            end
            return nil
        end,
        canRead = function(node, alias)
            if node._mode ~= "runtime" then
                logging.violate(
                    "staged_state.invalid_surface",
                    "stagedState.runtimeOwned.read: alias '%s' is not runtime-owned storage",
                    tostring(alias))
                return false
            end
            return true
        end,
        onUnknownRead = function(alias)
            logging.violate("staged_state.unknown_alias", "stagedState.runtimeOwned.read: unknown alias '%s'",
                tostring(alias))
        end,
    }

    local stagedWriteBackend = {
        readRoot = function(root)
            if staging[root.alias] == nil then
                loadRootIntoStaging(root)
            end
            return staging[root.alias]
        end,
        canWrite = function(node, alias)
            if node._mode == "runtime" then
                logging.violate(
                    "staged_state.invalid_surface",
                    "stagedState.write: alias '%s' is runtime-owned; use stagedState.runtimeOwned on the read side",
                    tostring(alias))
                return false
            end
            return true
        end,
        writeRoot = writeRootToStaging,
        writeAliasValue = function(node, aliasValue)
            staging[node.alias] = aliasValue
        end,
        onUnknownWrite = function(alias)
            logging.violate("staged_state.unknown_alias", "stagedState.write: unknown alias '%s'", tostring(alias))
        end,
    }

    local readonlyProxy = setmetatable({}, {
        __index = function(_, key)
            local value = staging[key]
            local node = aliasNodes[key]
            if node and node._mode == "runtime" and persistentState and type(persistentState._readRoot) == "function" then
                value = persistentState._readRoot(node)
            end
            if node and node.type == "table" then
                return ClonePersistedValue(value)
            end
            return value
        end,
        __newindex = function()
            logging.violate("staged_state.readonly_view_write", "stagedState.view is read-only; use stagedState.write")
        end,
        __pairs = function()
            return function(_, key)
                local nextKey, value = next(staging, key)
                local node = aliasNodes[nextKey]
                if node and node._mode == "runtime" and persistentState and type(persistentState._readRoot) == "function" then
                    value = persistentState._readRoot(node)
                end
                if node and node.type == "table" then
                    value = ClonePersistedValue(value)
                end
                return nextKey, value
            end, staging, nil
        end,
    })

    local function readStagingValue(alias)
        return storageInternal.readAlias(aliasNodes, stagedReadBackend, alias)
    end

    local function readRuntimeOwnedValue(alias)
        return storageInternal.readAlias(aliasNodes, runtimeOwnedReadBackend, alias)
    end

    local runtimeOwnedFieldOwner = {
        read = readRuntimeOwnedValue,
        getAliasSchema = function(alias)
            return aliasNodes[alias]
        end,
    }

    local function getRuntimeOwnedFieldHandleForNode(alias, node)
        local cached = runtimeOwnedFieldHandles[alias]
        if cached then
            return cached
        end

        local field = storageInternal.field.createKnown(runtimeOwnedFieldOwner, alias, node, "stagedState.runtimeOwned.get")
        runtimeOwnedFieldHandles[alias] = field
        return field
    end

    local function writeStagingValue(alias, value)
        storageInternal.writeAlias(aliasNodes, stagedWriteBackend, alias, value)
    end

    local function getTableHandleForNode(alias, node)
        local cached = tableHandles[alias]
        if cached then
            return cached
        end

        local tableOpts = {
            readRoot = function(root)
                if root._mode == "runtime" and persistentState and type(persistentState._readRoot) == "function" then
                    return persistentState._readRoot(root)
                end
                if staging[root.alias] == nil then
                    loadRootIntoStaging(root)
                end
                return staging[root.alias]
            end,
            normalizedRoot = true,
        }
        if node._mode ~= "runtime" then
            tableOpts.writeRoot = writeRootToStaging
        end

        local handle = storageInternal.table.CreateTableHandle(node, tableOpts)
        tableHandles[alias] = handle
        return handle
    end

    local function getTableHandle(alias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("staged_state.unknown_alias", "stagedState.table: unknown alias '%s'", tostring(alias))
            return nil
        end
        if node.type ~= "table" or node._isBitAlias then
            logging.violate("staged_state.invalid_table_alias", "stagedState.table: alias '%s' is not table storage", tostring(alias))
            return nil
        end
        if node._mode == "runtime" then
            logging.violate("staged_state.invalid_surface",
                "stagedState.table: alias '%s' is runtime-owned; use stagedState.runtimeOwned.table", tostring(alias))
            return nil
        end
        return getTableHandleForNode(alias, node)
    end

    local function resetAliasValue(alias)
        local node = aliasNodes[alias]
        if not node then
            logging.violate("staged_state.unknown_alias", "stagedState.reset: unknown alias '%s'", tostring(alias))
            return
        end

        local defaultValue = ClonePersistedValue(node.default)
        writeStagingValue(alias, defaultValue)
    end

    local function resetAll(opts)
        local exclude = type(opts) == "table" and type(opts.exclude) == "table" and opts.exclude or {}
        local count = 0

        for _, root in ipairs(stagedRootNodes) do
            local alias = root.alias
            if root._mode ~= "runtime" and alias ~= nil and not exclude[alias] then
                local current = readStagingValue(alias)
                if not storageInternal.valuesEqual(root, current, root.default) then
                    resetAliasValue(alias)
                    count = count + 1
                end
            end
        end

        return count > 0, count
    end

    copyConfigToStaging()
    clearDirty()

    local stagedState
    local function getFieldHandleForNode(alias, node)
        local cached = fieldHandles[alias]
        if cached then
            return cached
        end

        local field = storageInternal.field.createKnown(stagedState, alias, node, "stagedState.get")
        fieldHandles[alias] = field
        return field
    end

    local function getDataObject(alias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("staged_state.unknown_alias", "stagedState.get: unknown alias '%s'", tostring(alias))
            return nil
        end
        if node._mode == "runtime" then
            logging.violate(
                "staged_state.invalid_surface",
                "stagedState.get: alias '%s' is runtime-owned; use stagedState.runtimeOwned.get",
                tostring(alias))
            return nil
        end
        if node.type == "table" and not node._isBitAlias then
            return getTableHandleForNode(alias, node)
        end
        return getFieldHandleForNode(alias, node)
    end

    local function getRuntimeOwnedDataObject(alias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("staged_state.unknown_alias", "stagedState.runtimeOwned.get: unknown alias '%s'",
                tostring(alias))
            return nil
        end
        if node._mode ~= "runtime" then
            logging.violate(
                "staged_state.invalid_surface",
                "stagedState.runtimeOwned.get: alias '%s' is not runtime-owned storage",
                tostring(alias))
            return nil
        end
        if node.type == "table" and not node._isBitAlias then
            return getTableHandleForNode(alias, node)
        end
        return getRuntimeOwnedFieldHandleForNode(alias, node)
    end

    local function getRuntimeOwnedTable(alias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("staged_state.unknown_alias", "stagedState.runtimeOwned.table: unknown alias '%s'",
                tostring(alias))
            return nil
        end
        if node._mode ~= "runtime" then
            logging.violate("staged_state.invalid_surface",
                "stagedState.runtimeOwned.table: alias '%s' is not runtime-owned storage", tostring(alias))
            return nil
        end
        if node.type ~= "table" or node._isBitAlias then
            logging.violate("staged_state.invalid_table_alias",
                "stagedState.runtimeOwned.table: alias '%s' is not table storage", tostring(alias))
            return nil
        end
        return getTableHandleForNode(alias, node)
    end

    stagedState = {
        view = readonlyProxy,
        get = function(alias)
            return getDataObject(alias)
        end,
        read = function(alias)
            return readStagingValue(alias)
        end,
        table = function(alias)
            return getTableHandle(alias)
        end,
        runtimeOwned = {
            read = readRuntimeOwnedValue,
            get = getRuntimeOwnedDataObject,
            table = getRuntimeOwnedTable,
        },
        field = function(alias)
            return storageInternal.field.create(stagedState, alias, "stagedState.field")
        end,
        getAliasSchema = function(alias)
            return aliasNodes[alias]
        end,
        write = function(alias, value)
            writeStagingValue(alias, value)
        end,
        reset = function(alias)
            resetAliasValue(alias)
        end,
        resetAll = resetAll,
        _reloadFromConfig = function()
            if persistentState and type(persistentState._reloadFromConfig) == "function" then
                persistentState._reloadFromConfig()
            end
            copyConfigToStaging()
            clearDirty()
        end,
        _flushToConfig = function()
            copyStagingToConfig()
            clearDirty()
        end,
        _hasConfigChanges = function()
            return dirty
        end,
        _captureDirtyConfigSnapshot = captureDirtyConfigSnapshot,
        _restoreConfigSnapshot = restoreConfigSnapshot,
        isDirty = function()
            return dirty
        end,
        auditMismatches = function()
            local mismatches = {}
            for _, root in ipairs(stagedRootNodes) do
                if not root._persist or root._mode == "runtime" then
                    goto continue_root
                end
                local persistedValue = readPersistedConfigValue(root)
                if persistedValue == nil then
                    persistedValue = ClonePersistedValue(root.default)
                end
                persistedValue = NormalizeStorageValue(root, persistedValue)
                if not storageInternal.valuesEqual(root, persistedValue, staging[root.alias]) then
                    table.insert(mismatches, root.alias)
                end
                if root.type == "packedInt" then
                    for _, child in ipairs(root._bitAliases or {}) do
                        local childValue = DecodePackedChild(child, persistedValue)
                        if not storageInternal.valuesEqual(child, childValue, staging[child.alias]) then
                            table.insert(mismatches, child.alias)
                        end
                    end
                end
                ::continue_root::
            end
            return mismatches
        end,
    }

    return stagedState
end

return {
    createStagedState = createStagedState,
}
