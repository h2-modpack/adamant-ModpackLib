local deps = ...

local logging = deps.logging
local storageInternal = deps.storage
local values = deps.values
local ClonePersistedValue = values.deepCopy
local NormalizeStorageValue = storageInternal.NormalizeStorageValue
local DecodePackedChild = storageInternal.packed.DecodePackedChild

---@class AuthorSession
---@field view table<string, any>
---@field get fun(alias: string): StorageField|StorageTableSession|nil
---@field read fun(alias: string): any
---@field field fun(alias: string): StorageField
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)
---@field getAliasSchema fun(alias: string): StorageNode|PackedBitNode|nil
---@field resetToDefaults fun(opts: table|nil): boolean, number

---@param storageConfig StorageConfigAdapter
---@param storage StorageSchema
---@return Session
local function createSession(storageConfig, storage)
    local sessionRootNodes = storageInternal.getSessionRoots(storage)
    local aliasNodes = storageInternal.getAliases(storage)
    local staging = {}
    local dirty = false
    local dirtyRoots = {}
    local configEntries = {}
    local tableHandles = {}

    for _, root in ipairs(sessionRootNodes) do
        if root._persist then
            configEntries[root.alias] = storageConfig.getEntry(root._storageKey)
        end
    end

    local function readConfigValue(root)
        if not root._persist then
            return nil
        end
        local entry = configEntries and configEntries[root.alias] or nil
        if entry then
            return entry:get()
        end
        return storageConfig.readValue(root._storageKey)
    end

    local function writeConfigValue(root, value)
        if not root._persist then
            return
        end
        local entry = configEntries and configEntries[root.alias] or nil
        if entry then
            entry:set(value)
            return
        end
        storageConfig.writeValue(root._storageKey, value)
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
        for _, root in ipairs(sessionRootNodes) do
            loadRootIntoStaging(root)
        end
    end

    local function copyStagingToConfig()
        for _, root in ipairs(sessionRootNodes) do
            if dirtyRoots[root.alias] then
                writeConfigValue(root, staging[root.alias])
            end
        end
    end

    local function captureDirtyConfigSnapshot()
        local snapshot = {}
        for _, root in ipairs(sessionRootNodes) do
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

    local sessionReadBackend = {
        readRoot = function(root)
            return staging[root.alias]
        end,
        onUnknownRead = function(alias)
            logging.violate("session.unknown_alias", "session.read: unknown alias '%s'", tostring(alias))
        end,
    }

    local sessionWriteBackend = {
        readRoot = function(root)
            if staging[root.alias] == nil then
                loadRootIntoStaging(root)
            end
            return staging[root.alias]
        end,
        writeRoot = writeRootToStaging,
        writeAliasValue = function(node, aliasValue)
            staging[node.alias] = aliasValue
        end,
        onUnknownWrite = function(alias)
            logging.violate("session.unknown_alias", "session.write: unknown alias '%s'", tostring(alias))
        end,
    }

    local readonlyProxy = setmetatable({}, {
        __index = function(_, key)
            local value = staging[key]
            local node = aliasNodes[key]
            if node and node.type == "table" then
                return ClonePersistedValue(value)
            end
            return value
        end,
        __newindex = function()
            logging.violate("session.readonly_view_write", "session.view is read-only; use session.write")
        end,
        __pairs = function()
            return function(_, key)
                local nextKey, value = next(staging, key)
                local node = aliasNodes[nextKey]
                if node and node.type == "table" then
                    value = ClonePersistedValue(value)
                end
                return nextKey, value
            end, staging, nil
        end,
    })

    local function readStagingValue(alias)
        return storageInternal.readAlias(aliasNodes, sessionReadBackend, alias)
    end

    local function writeStagingValue(alias, value)
        storageInternal.writeAlias(aliasNodes, sessionWriteBackend, alias, value)
    end

    local function getTableHandleForNode(alias, node)
        local cached = tableHandles[alias]
        if cached then
            return cached
        end

        local handle = storageInternal.table.CreateTableHandle(node, {
            readRoot = function(root)
                if staging[root.alias] == nil then
                    loadRootIntoStaging(root)
                end
                return staging[root.alias]
            end,
            writeRoot = writeRootToStaging,
            normalizedRoot = true,
        })
        tableHandles[alias] = handle
        return handle
    end

    local function getTableHandle(alias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("session.unknown_alias", "session.table: unknown alias '%s'", tostring(alias))
            return nil
        end
        if node.type ~= "table" or node._isBitAlias then
            logging.violate("session.invalid_table_alias", "session.table: alias '%s' is not table storage", tostring(alias))
            return nil
        end
        return getTableHandleForNode(alias, node)
    end

    local function resetAliasValue(alias)
        local node = aliasNodes[alias]
        if not node then
            logging.violate("session.unknown_alias", "session.reset: unknown alias '%s'", tostring(alias))
            return
        end

        local defaultValue = ClonePersistedValue(node.default)
        writeStagingValue(alias, defaultValue)
    end

    copyConfigToStaging()
    clearDirty()

    local session
    local function getDataObject(alias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("session.unknown_alias", "session.get: unknown alias '%s'", tostring(alias))
            return nil
        end
        if node.type == "table" and not node._isBitAlias then
            return getTableHandleForNode(alias, node)
        end
        return storageInternal.field.createKnown(session, alias, node, "session.get")
    end

    session = {
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
        field = function(alias)
            return storageInternal.field.create(session, alias, "session.field")
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
        _reloadFromConfig = function()
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
            for _, root in ipairs(sessionRootNodes) do
                if not root._persist then
                    goto continue_root
                end
                local persistedValue = readConfigValue(root)
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

    return session
end

--- Narrows a full staged session to the module author UI surface.
--- Host internals keep the private commit/reload/snapshot methods.
---@param session Session
---@param opts table
---@return AuthorSession
local function createAuthorSession(session, opts)
    return {
        view = session.view,
        get = session.get,
        read = session.read,
        table = session.table,
        field = session.field,
        write = session.write,
        reset = session.reset,
        getAliasSchema = session.getAliasSchema,
        resetToDefaults = opts.resetToDefaults,
    }
end

return {
    createSession = createSession,
    createAuthorSession = createAuthorSession,
}
