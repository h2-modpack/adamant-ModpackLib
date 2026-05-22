local deps = ...

local logging = deps.logging
local storageInternal = deps.storage
local values = deps.values
local ClonePersistedValue = values.deepCopy
local NormalizeStorageValue = storageInternal.NormalizeStorageValue

local function create(storageConfig, storage)
    local persistentState = {}

    local aliasNodes = storageInternal.getAliases(storage)
    local tableHandles = {}
    local fieldHandles = {}

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

    function persistentState.read(alias)
        return storageInternal.readAlias(aliasNodes, storeReadBackend, alias)
    end

    function persistentState.getAliasSchema(alias)
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
