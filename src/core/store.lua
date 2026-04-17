local internal = AdamantModpackLib_Internal
local chalk = rom.mods['SGG_Modding-Chalk']
local ui = internal.ui
public.store = public.store or {}
local storeApi = public.store

local function ClonePersistedValue(value)
    if type(value) == "table" then
        return rom.game.DeepCopyTable(value)
    end
    return value
end

local function BuildManagedStorage(definition)
    if type(definition) ~= "table" then
        return nil
    end

    if definition.stateSchema ~= nil or definition.options ~= nil then
        error("legacy definition.stateSchema/options are no longer supported; use definition.storage", 2)
    end

    if definition.storage ~= nil
        or definition.special ~= nil
        or definition.id ~= nil
    then
        if type(definition.storage) == "table" then
            return definition.storage
        end
        return nil
    end

    if #definition > 0 then
        error("createStore expects a module definition table; raw storage arrays are not supported", 2)
    end
    return nil
end

local function NormalizeStorageValue(node, value)
    local storageType = node and node.type and public.registry.storage[node.type] or nil
    if storageType and type(storageType.normalize) == "function" then
        return storageType.normalize(node, value)
    end
    return value
end

local ConfigBackendCache = setmetatable({}, { __mode = "k" })

local function GetChalkSectionAndKey(configKey)
    if type(configKey) == "table" then
        local len = #configKey
        if len == 0 then
            return nil, nil
        end
        if len == 1 then
            return "config", tostring(configKey[1])
        end
        return "config." .. table.concat(configKey, ".", 1, len - 1), tostring(configKey[len])
    end
    return "config", tostring(configKey)
end

local function GetConfigBackend(config)
    if not chalk or type(chalk.original) ~= "function" then
        return nil
    end

    local ok, rawConfig = pcall(chalk.original, config)
    if not ok or type(rawConfig) ~= "table" or type(rawConfig.entries) ~= "table" then
        return nil
    end

    local backend = ConfigBackendCache[rawConfig]
    if backend then
        return backend
    end

    local entryIndex = {}
    for descriptor, entry in pairs(rawConfig.entries) do
        local section = descriptor.section
        local key = descriptor.key
        if section ~= nil and key ~= nil then
            local sectionEntries = entryIndex[section]
            if not sectionEntries then
                sectionEntries = {}
                entryIndex[section] = sectionEntries
            end
            sectionEntries[key] = entry
        end
    end

    local pathEntryCache = {}
    backend = {}

    function backend.getEntry(configKey)
        local pathKey = ui.StorageKey(configKey)
        local cached = pathEntryCache[pathKey]
        if cached ~= nil then
            return cached or nil
        end

        local section, key = GetChalkSectionAndKey(configKey)
        local entry = section and entryIndex[section] and entryIndex[section][key] or nil
        if entry and type(entry.get) == "function" and type(entry.set) == "function" then
            pathEntryCache[pathKey] = entry
            return entry
        end

        pathEntryCache[pathKey] = false
        return nil
    end

    function backend.readValue(configKey)
        local entry = backend.getEntry(configKey)
        if entry then
            return entry:get()
        end
        return nil
    end

    function backend.writeValue(configKey, value)
        local entry = backend.getEntry(configKey)
        if entry then
            entry:set(value)
            return true
        end
        return false
    end

    backend.rawConfig = rawConfig
    ConfigBackendCache[rawConfig] = backend
    return backend
end

local function CreateUiState(modConfig, configBackend, storage)
    local persistedRootNodes = public.storage.getRoots(storage)
    local transientRootNodes = type(storage) == "table" and (rawget(storage, "_transientRootNodes") or {}) or {}
    local aliasNodes = public.storage.getAliases(storage)
    local staging = {}
    local dirty = false
    local dirtyRoots = {}
    local configEntries = {}

    if configBackend then
        for _, root in ipairs(persistedRootNodes) do
            configEntries[root.alias] = configBackend.getEntry(root.configKey)
        end
    else
        configEntries = nil
    end

    local function readConfigValue(root)
        local entry = configEntries and configEntries[root.alias] or nil
        if entry then
            return entry:get()
        end
        return public.accessors.readNestedPath(modConfig, root.configKey)
    end

    local function writeConfigValue(root, value)
        local entry = configEntries and configEntries[root.alias] or nil
        if entry then
            entry:set(value)
            return
        end
        public.accessors.writeNestedPath(modConfig, root.configKey, value)
    end

    local function syncPackedChildren(root, packedValue)
        for _, child in ipairs(root._bitAliases or {}) do
            local rawValue = public.accessors.readPackedBits(packedValue, child.offset, child.width)
            if child.type == "bool" then
                rawValue = rawValue ~= 0
            end
            staging[child.alias] = NormalizeStorageValue(child, rawValue)
        end
    end

    local function writeRootToStaging(root, value)
        local normalized = NormalizeStorageValue(root, value)
        staging[root.alias] = normalized
        if root.type == "packedInt" then
            syncPackedChildren(root, normalized)
        end
        if root._lifetime ~= "transient" then
            dirtyRoots[root.alias] = true
            dirty = true
        end
    end

    local function loadPersistedRootIntoStaging(root)
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

    local function loadTransientRootIntoStaging(root)
        local value = ClonePersistedValue(root.default)
        staging[root.alias] = NormalizeStorageValue(root, value)
    end

    local function copyConfigToStaging()
        for _, root in ipairs(persistedRootNodes) do
            loadPersistedRootIntoStaging(root)
        end
    end

    local function resetTransientToDefaults()
        for _, root in ipairs(transientRootNodes) do
            loadTransientRootIntoStaging(root)
        end
    end

    local function copyStagingToConfig()
        for _, root in ipairs(persistedRootNodes) do
            if dirtyRoots[root.alias] then
                writeConfigValue(root, staging[root.alias])
            end
        end
    end

    local function captureDirtyConfigSnapshot()
        local snapshot = {}
        for _, root in ipairs(persistedRootNodes) do
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

    local readonlyProxy = setmetatable({}, {
        __index = function(_, key)
            return staging[key]
        end,
        __newindex = function()
            error("uiState view is read-only; use state.set/update/toggle", 2)
        end,
        __pairs = function()
            return next, staging, nil
        end,
    })

    local function readStagingValue(alias)
        return staging[alias], aliasNodes[alias]
    end

    local function writeStagingValue(alias, value)
        local node = aliasNodes[alias]
        if not node then
            if internal.logging and internal.logging.warnIf then
                internal.logging.warnIf("uiState.set: unknown alias '%s'; value will not be persisted", tostring(alias))
            end
            return
        end

        if node._isBitAlias then
            local parent = node.parent
            local packedValue = staging[parent.alias]
            if packedValue == nil then
                if parent._lifetime == "transient" then
                    loadTransientRootIntoStaging(parent)
                else
                    loadPersistedRootIntoStaging(parent)
                end
                packedValue = staging[parent.alias]
            end
            local normalized = NormalizeStorageValue(node, value)
            local encoded = node.type == "bool" and (normalized and 1 or 0) or normalized
            local nextPacked = public.accessors.writePackedBits(packedValue, node.offset, node.width, encoded)
            writeRootToStaging(parent, nextPacked)
            staging[node.alias] = normalized
            return
        end

        writeRootToStaging(node, value)
    end

    local function resetAliasValue(alias)
        local node = aliasNodes[alias]
        if not node then
            if internal.logging and internal.logging.warnIf then
                internal.logging.warnIf("uiState.reset: unknown alias '%s'; value will not be reset", tostring(alias))
            end
            return
        end

        local defaultValue = ClonePersistedValue(node.default)
        writeStagingValue(alias, defaultValue)
    end

    copyConfigToStaging()
    resetTransientToDefaults()
    clearDirty()

    return {
        view = readonlyProxy,
        get = function(alias)
            return readStagingValue(alias)
        end,
        set = function(alias, value)
            writeStagingValue(alias, value)
        end,
        reset = function(alias)
            resetAliasValue(alias)
        end,
        update = function(alias, updater)
            local current = readStagingValue(alias)
            writeStagingValue(alias, updater(current))
        end,
        toggle = function(alias)
            local current = readStagingValue(alias)
            writeStagingValue(alias, not (current == true))
        end,
        reloadFromConfig = function()
            copyConfigToStaging()
            resetTransientToDefaults()
            clearDirty()
        end,
        flushToConfig = function()
            copyStagingToConfig()
            clearDirty()
        end,
        _captureDirtyConfigSnapshot = captureDirtyConfigSnapshot,
        _restoreConfigSnapshot = restoreConfigSnapshot,
        isDirty = function()
            return dirty
        end,
        getAliasNode = function(alias)
            return aliasNodes[alias]
        end,
        collectConfigMismatches = function()
            local mismatches = {}
            for _, root in ipairs(persistedRootNodes) do
                local persistedValue = readConfigValue(root)
                if persistedValue == nil then
                    persistedValue = ClonePersistedValue(root.default)
                end
                persistedValue = NormalizeStorageValue(root, persistedValue)
                if not public.storage.valuesEqual(root, persistedValue, staging[root.alias]) then
                    table.insert(mismatches, root.alias)
                end
                if root.type == "packedInt" then
                    for _, child in ipairs(root._bitAliases or {}) do
                        local childValue = public.accessors.readPackedBits(persistedValue, child.offset, child.width)
                        if child.type == "bool" then
                            childValue = childValue ~= 0
                        end
                        childValue = NormalizeStorageValue(child, childValue)
                        if not public.storage.valuesEqual(child, childValue, staging[child.alias]) then
                            table.insert(mismatches, child.alias)
                        end
                    end
                end
            end
            return mismatches
        end,
    }
end

--- Creates a managed store wrapper around a module definition and its persisted config table.
---@param modConfig table Module config table used for persisted reads and writes.
---@param definition table Module definition declaring storage, ui, and mutation behavior.
---@param dataDefaults table|nil Optional defaults table used to seed missing storage defaults.
---@return table store Managed store instance for config, UI state, and mutation lifecycle.
function storeApi.create(modConfig, definition, dataDefaults)
    local backend = GetConfigBackend(modConfig)
    local store = {}
    local storage = BuildManagedStorage(definition)

    if storage and type(dataDefaults) == "table" then
        for _, node in ipairs(storage) do
            if node.lifetime ~= "transient" and node.default == nil then
                local key = node.configKey or node.alias
                if key ~= nil then
                    node.default = public.accessors.readNestedPath(dataDefaults, key)
                end
            end
        end
    end
    local label = type(definition) == "table"
        and tostring(definition.name or definition.id or _PLUGIN.guid or "module")
        or tostring(_PLUGIN.guid or "module")

    if type(definition) == "table" and internal.libConfig.DebugMode == true then
        public.definition.validate(definition, label)
    end

    if storage then
        public.storage.validate(storage, label)
    end

    local aliasNodes = storage and public.storage.getAliases(storage) or {}
    local persistedAliasNodes = storage and (rawget(storage, "_persistedAliasNodes") or {}) or {}
    local rootByKey = storage and (rawget(storage, "_rootByKey") or {}) or {}

    local function readRaw(configKey)
        local raw
        if backend then
            raw = backend.readValue(configKey)
        end
        if raw == nil then
            raw = public.accessors.readNestedPath(modConfig, configKey)
        end
        return raw
    end

    local function writeRaw(configKey, value)
        if backend and backend.writeValue(configKey, value) then
            return
        end
        public.accessors.writeNestedPath(modConfig, configKey, value)
    end

    local function readRootNode(root)
        local raw = readRaw(root.configKey)
        if raw == nil then
            raw = ClonePersistedValue(root.default)
        end
        return NormalizeStorageValue(root, raw)
    end

    local function writeRootNode(root, value)
        writeRaw(root.configKey, NormalizeStorageValue(root, value))
    end

    --- Reads a persisted storage value by alias, config key, or nested config path.
    ---@param keyOrAlias string|table Alias, config key, or nested config path to read.
    ---@return any value Resolved value, normalized through the owning storage type when applicable.
    function store.read(keyOrAlias)
        if type(keyOrAlias) == "string" then
            local node = aliasNodes[keyOrAlias]
                if node then
                    if node._lifetime == "transient" then
                        internal.logging.warn(
                            "store.read: alias '%s' is transient; use store.uiState for UI-only state",
                            tostring(keyOrAlias))
                        return nil
                    end
                if node._isBitAlias then
                    local packed = readRootNode(node.parent)
                    local rawValue = public.accessors.readPackedBits(packed, node.offset, node.width)
                    if node.type == "bool" then
                        rawValue = rawValue ~= 0
                    end
                    return NormalizeStorageValue(node, rawValue)
                end
                return readRootNode(node)
            end

            local root = rootByKey[ui.StorageKey(keyOrAlias)]
            if root then
                return readRootNode(root)
            end
        end
        return readRaw(keyOrAlias)
    end

    --- Writes a persisted storage value by alias, config key, or nested config path.
    ---@param keyOrAlias string|table Alias, config key, or nested config path to write.
    ---@param value any Value to persist, normalized through the owning storage type when applicable.
    function store.write(keyOrAlias, value)
        if type(keyOrAlias) == "string" then
            local node = aliasNodes[keyOrAlias]
            if node then
                if node._lifetime == "transient" then
                    internal.logging.warn(
                        "store.write: alias '%s' is transient; use store.uiState for UI-only state",
                        tostring(keyOrAlias))
                    return
                end
                if node._isBitAlias then
                    local parent = node.parent
                    local currentPacked = readRootNode(parent)
                    local normalized = NormalizeStorageValue(node, value)
                    local encoded = node.type == "bool" and (normalized and 1 or 0) or normalized
                    local nextPacked = public.accessors.writePackedBits(currentPacked, node.offset, node.width, encoded)
                    writeRootNode(parent, nextPacked)
                    return
                end
                writeRootNode(node, value)
                return
            end

            local root = rootByKey[ui.StorageKey(keyOrAlias)]
            if root then
                writeRootNode(root, value)
                return
            end
        end
        writeRaw(keyOrAlias, value)
    end

    --- Reads a packed bitfield directly from a persisted config key.
    ---@param configKey string|table Config key or nested config path for the packed integer root.
    ---@param offset number Zero-based starting bit offset.
    ---@param width number Number of bits to read.
    ---@return number value Decoded integer value for the requested bit range.
    function store.readBits(configKey, offset, width)
        return public.accessors.readPackedBits(readRaw(configKey), offset, width)
    end

    --- Writes a packed bitfield directly into a persisted config key.
    ---@param configKey string|table Config key or nested config path for the packed integer root.
    ---@param offset number Zero-based starting bit offset.
    ---@param width number Number of bits to write.
    ---@param value number Decoded integer value to encode into the requested bit range.
    function store.writeBits(configKey, offset, width, value)
        local current = math.floor(tonumber(readRaw(configKey)) or 0)
        local nextPacked = public.accessors.writePackedBits(current, offset, width, value)
        writeRaw(configKey, nextPacked)
    end

    --- Returns packed child aliases for a packed root alias.
    ---@param alias string Packed root alias.
    ---@return table aliases Ordered list of `{ alias = string, label = string }` entries.
    function store.getPackedAliases(alias)
        local node = aliasNodes[alias]
        if not node or node.type ~= "packedInt" then
            return {}
        end

        local packedAliases = {}
        for _, child in ipairs(node._bitAliases or {}) do
            packedAliases[#packedAliases + 1] = {
                alias = child.alias,
                label = child.label or child.alias,
            }
        end
        return packedAliases
    end

    store.storage = storage
    store.ui = nil
    store._persistedAliasNodes = persistedAliasNodes

    if storage then
        store.uiState = CreateUiState(modConfig, backend, storage)
    end

    return store
end
