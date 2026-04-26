local internal = AdamantModpackLib_Internal
local chalk = rom.mods['SGG_Modding-Chalk']
local storageInternal = internal.storage
local storeInternal = internal.store
local StorageKey = storageInternal.StorageKey
local readNestedPath = storeInternal.readNestedPath
local writeNestedPath = storeInternal.writeNestedPath
local ClonePersistedValue = storeInternal.ClonePersistedValue
local NormalizeStorageValue = storageInternal.NormalizeStorageValue

---@class ConfigBackendEntry
---@field get fun(self: ConfigBackendEntry): any
---@field set fun(self: ConfigBackendEntry, value: any)

---@class ConfigBackend
---@field rawConfig table
---@field getEntry fun(configKey: ConfigPath): ConfigBackendEntry|nil
---@field readValue fun(configKey: ConfigPath): any
---@field writeValue fun(configKey: ConfigPath, value: any): boolean

---@class Session
---@field view table<string, any>
---@field read fun(alias: string): any
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)
---@field _flushToConfig fun()
---@field _reloadFromConfig fun()
---@field _captureDirtyConfigSnapshot fun(): table[]
---@field _restoreConfigSnapshot fun(snapshot: table[]|nil)
---@field isDirty fun(): boolean
---@field auditMismatches fun(): string[]

---@class ModuleDefinition
---@field modpack string|nil
---@field id string|nil
---@field name string|nil
---@field shortName string|nil
---@field tooltip string|nil
---@field default boolean|nil
---@field affectsRunData boolean|nil
---@field storage StorageSchema|nil
---@field hashGroups table|nil
---@field patchPlan fun(store: ManagedStore): table|nil
---@field apply fun(store: ManagedStore)|nil
---@field revert fun(store: ManagedStore)|nil

---@class ManagedStore
---@field read fun(keyOrAlias: ConfigPath): any

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

---@param config table
---@return ConfigBackend|nil
local function GetConfigBackend(config)
    if not chalk then
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
        local pathKey = StorageKey(configKey)
        local cached = pathEntryCache[pathKey]
        if cached ~= nil then
            return cached or nil
        end

        local section, key = GetChalkSectionAndKey(configKey)
        local entry = section and entryIndex[section] and entryIndex[section][key] or nil
        if entry then
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

--- Creates a managed store wrapper around a prepared module definition and its persisted config table.
---@param modConfig table Module config table used for persisted reads and writes.
---@param definition ModuleDefinition Prepared module definition declaring storage and mutation behavior.
---@return ManagedStore store Managed store instance for config and mutation lifecycle.
---@return Session session Staged UI/session state for storage-backed controls.
function public.createStore(modConfig, definition)
    assert(type(definition) == "table" and definition._preparedDefinition == true,
        "createStore expects a prepared definition; call lib.prepareDefinition(...) first")
    local backend = GetConfigBackend(modConfig)
    local store = {}
    local storage = type(definition.storage) == "table" and definition.storage or nil
    local label = tostring(definition.name or definition.id or _PLUGIN.guid or "module")

    if storage then
        storageInternal.validate(storage, label)
    end

    local aliasNodes = storage and storageInternal.getAliases(storage) or {}
    local rootByKey = storage and (rawget(storage, "_rootByKey") or {}) or {}

    local function readRaw(configKey)
        local raw
        if backend then
            raw = backend.readValue(configKey)
        end
        if raw == nil then
            raw = readNestedPath(modConfig, configKey)
        end
        return raw
    end

    local function writeRaw(configKey, value)
        if backend and backend.writeValue(configKey, value) then
            return
        end
        writeNestedPath(modConfig, configKey, value)
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
                            "store.read: alias '%s' is transient; use session for UI-only state",
                            tostring(keyOrAlias))
                        return nil
                    end
                if node._isBitAlias then
                    local packed = readRootNode(node.parent)
                    local rawValue = storageInternal.readPackedBits(packed, node.offset, node.width)
                    if node.type == "bool" then
                        rawValue = rawValue ~= 0
                    end
                    return NormalizeStorageValue(node, rawValue)
                end
                return readRootNode(node)
            end

            local root = rootByKey[StorageKey(keyOrAlias)]
            if root then
                return readRootNode(root)
            end
        end
        return readRaw(keyOrAlias)
    end

    local function writeStoreValue(keyOrAlias, value)
        if type(keyOrAlias) == "string" then
            local node = aliasNodes[keyOrAlias]
            if node then
                if node._lifetime == "transient" then
                    internal.logging.warn(
                        "internal.store.writePersisted: alias '%s' is transient; use session for UI-only state",
                        tostring(keyOrAlias))
                    return
                end
                if node._isBitAlias then
                    local parent = node.parent
                    local currentPacked = readRootNode(parent)
                    local normalized = NormalizeStorageValue(node, value)
                    local encoded = node.type == "bool" and (normalized and 1 or 0) or normalized
                    local nextPacked = storageInternal.writePackedBits(currentPacked, node.offset, node.width, encoded)
                    writeRootNode(parent, nextPacked)
                    return
                end
                writeRootNode(node, value)
                return
            end

            local root = rootByKey[StorageKey(keyOrAlias)]
            if root then
                writeRootNode(root, value)
                return
            end
        end
        writeRaw(keyOrAlias, value)
    end

    local function getPackedAliases(alias)
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

    internal.store.bindManagedStore(store, {
        write = writeStoreValue,
        getPackedAliases = getPackedAliases,
    })

    local session = nil
    if storage then
        session = internal.store.createSession(modConfig, backend, storage)
    end

    return store, session
end

--- Resets persistent storage roots to defaults in a staged session.
---@param storage StorageSchema Validated storage schema.
---@param session Session Staged session returned by `lib.createStore`.
---@param opts table|nil Optional `{ exclude = { Alias = true } }` map.
---@return boolean changed True when at least one alias was reset.
---@return number count Number of aliases reset.
function public.resetStorageToDefaults(storage, session, opts)
    if type(storage) ~= "table" or type(session) ~= "table" then
        return false, 0
    end

    local exclude = type(opts) == "table" and type(opts.exclude) == "table" and opts.exclude or {}
    local count = 0

    for _, node in ipairs(storageInternal.getRoots(storage) or {}) do
        local alias = node.alias
        if alias ~= nil and not exclude[alias] then
            local current = session.read(alias)
            if not storageInternal.valuesEqual(node, current, node.default) then
                session.reset(alias)
                count = count + 1
            end
        end
    end

    return count > 0, count
end
