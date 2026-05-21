local deps = ...

local logging = deps.logging
local storageInternal = deps.storage
local values = deps.values
local managedStoreState = setmetatable({}, { __mode = "k" })
local ClonePersistedValue = values.deepCopy
local NormalizeStorageValue = storageInternal.NormalizeStorageValue

local function bindManagedStore(store, state)
    managedStoreState[store] = state
end

local function writePersisted(store, alias, value)
    local state = store and managedStoreState[store] or nil
    if not state then
        logging.violate("store.invalid_managed_store", "moduleState.writePersisted expects a managed store")
    end
    return state.write(alias, value)
end

local function create(storageConfig, storage)
    local store = {}

    local aliasNodes = storageInternal.getAliases(storage)
    local tableHandles = {}

    local function readRaw(alias)
        return storageConfig.readValue(alias)
    end

    local function writeRaw(alias, value)
        storageConfig.writeValue(alias, value)
    end

    local function readRootNode(root)
        if root._persist then
            local raw = readRaw(root._storageKey)
            if raw ~= nil then
                return raw
            end
        end
        return ClonePersistedValue(root.default)
    end

    local function writeRootNode(root, value)
        if root._persist then
            writeRaw(root._storageKey, NormalizeStorageValue(root, value))
        end
    end

    local function hydratePersistRoot(root)
        if not root._persist then
            return
        end

        local raw = readRaw(root._storageKey)
        local source = raw
        if source == nil then
            source = ClonePersistedValue(root.default)
        end
        local normalized = NormalizeStorageValue(root, source)
        if raw ~= nil and values.deepEqual(raw, normalized) then
            return
        end

        if raw == nil and storageConfig.ensureValue(root._storageKey, normalized) then
            return
        end
        writeRaw(root._storageKey, normalized)
    end

    for _, root in ipairs(storageInternal.getPersistRoots(storage)) do
        hydratePersistRoot(root)
    end

    local storeReadBackend = {
        readRoot = readRootNode,
        canRead = function(node, alias)
            if not node._persist then
                logging.violate(
                    "store.invalid_surface",
                    "store.read: alias '%s' is session-only; use session for UI-only state",
                    tostring(alias))
                return false
            end
            return true
        end,
        onUnknownRead = function(alias)
            logging.violate("store.unknown_alias", "store.read: unknown storage alias '%s'", tostring(alias))
        end,
    }

    local storeWriteBackend = {
        readRoot = readRootNode,
        writeRoot = function(root, rootValue)
            writeRootNode(root, rootValue)
            return true
        end,
        canWrite = function(node, alias)
            if not node._persist then
                logging.violate(
                    "store.invalid_surface",
                    "moduleState.writePersisted: alias '%s' is session-only; use session for UI-only state",
                    tostring(alias))
                return false
            end
            return true
        end,
        onUnknownWrite = function(alias)
            logging.violate("store.unknown_alias", "moduleState.writePersisted: unknown storage alias '%s'",
                tostring(alias))
        end,
    }

    function store.read(alias)
        return storageInternal.readAlias(aliasNodes, storeReadBackend, alias)
    end

    function store.getAliasSchema(alias)
        return aliasNodes[alias]
    end

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

    function store.table(alias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("store.unknown_alias", "store.table: unknown storage alias '%s'", tostring(alias))
            return nil
        end
        if node.type ~= "table" or node._isBitAlias then
            logging.violate("store.invalid_table_alias", "store.table: alias '%s' is not table storage", tostring(alias))
            return nil
        end
        if not node._persist then
            logging.violate("store.invalid_surface", "store.table: alias '%s' is session-only; use session.table()",
                tostring(alias))
            return nil
        end
        return getTableHandleForNode(alias, node)
    end

    function store.get(alias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            logging.violate("store.unknown_alias", "store.get: unknown storage alias '%s'", tostring(alias))
            return nil
        end
        if not node._persist then
            logging.violate(
                "store.invalid_surface",
                "store.get: alias '%s' is session-only; use session for UI-only state",
                tostring(alias))
            return nil
        end
        if node.type == "table" and not node._isBitAlias then
            return getTableHandleForNode(alias, node)
        end
        return storageInternal.field.createKnown(store, alias, node, "store.get")
    end

    local function writeStoreValue(alias, value)
        storageInternal.writeAlias(aliasNodes, storeWriteBackend, alias, value)
    end

    bindManagedStore(store, {
        write = writeStoreValue,
    })

    return store
end

return {
    create = create,
    writePersisted = writePersisted,
}
