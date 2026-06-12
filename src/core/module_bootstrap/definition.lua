local deps = ...

local logging = deps.logging
local storage = deps.storage
local values = deps.values
local coordinator = deps.coordinator
local moduleRegistry = deps.moduleRegistry
local plugin = deps.plugin

local definitionApi = {}

local KnownDefinitionKeys = {
    modpack = true,
    id = true,
    name = true,
    shortName = true,
    tooltip = true,
    storage = true,
    cache = true,
    actions = true,
}

local BuiltInStorageNodes = {
    { type = "bool", alias = "Enabled", default = false },
    { type = "bool", alias = "DebugMode", default = false, hash = false },
    {
        type = "int",
        alias = "__Modpack_PackRestoreMarker",
        default = 0,
        min = 0,
        max = 2,
        hash = false,
    },
}

local BuiltInStorageAliases = {
    Enabled = true,
    DebugMode = true,
    __Modpack_PackRestoreMarker = true,
}

local StableIdentifierPattern = "^[A-Za-z][A-Za-z0-9_]*$"
local StableIdentifierDescription = "must start with a letter and contain only letters, digits, and underscores"
local InternalPathSeparator = "-"
local InternalIdentifierDescription =
    "must start with '_' and contain '-'-separated stable identifier segments"


local KnownStructuralSurfaceKeys = {
    hasQuickContent = true,
}

local function IsStableIdentifier(value)
    return type(value) == "string" and string.match(value, StableIdentifierPattern) ~= nil
end

local function IsInternalIdentifier(value)
    if type(value) ~= "string" or string.byte(value, 1) ~= 95 then
        return false
    end

    local rest = string.sub(value, 2)
    if rest == "" then
        return false
    end

    local segmentStart = 1
    while true do
        local separatorStart, separatorEnd = string.find(rest, InternalPathSeparator, segmentStart, true)
        local segment = separatorStart ~= nil
            and string.sub(rest, segmentStart, separatorStart - 1)
            or string.sub(rest, segmentStart)
        if not IsStableIdentifier(segment) then
            return false
        end
        if separatorStart == nil then
            return true
        end
        segmentStart = separatorEnd + 1
    end
end

local function NormalizeStructuralSurface(surface)
    if surface == nil then
        return nil
    end
    if type(surface) ~= "table" then
        logging.violate(
            "definition.invalid_args",
            "prepareDefinition: structural surface must be a table when provided"
        )
    end

    for key in pairs(surface) do
        if not KnownStructuralSurfaceKeys[key] then
            logging.violate("definition.invalid_args", "prepareDefinition: unknown option '%s'", tostring(key))
        end
    end

    if surface.hasQuickContent ~= nil and type(surface.hasQuickContent) ~= "boolean" then
        logging.violate("definition.invalid_args", "prepareDefinition: hasQuickContent must be boolean when provided")
    end

    return {
        hasQuickContent = surface.hasQuickContent == true,
    }
end

local function CompareStrings(a, b)
    return a < b
end

local function IsTrustedInternalAction(key, internalActions)
    return type(key) == "string" and internalActions ~= nil and internalActions[key] == true
end

local function PrepareActions(definition, prefix, internalActions)
    local actions = definition.actions
    if actions == nil then
        definition.actions = {}
        definition._actionOrder = {}
        return
    end
    if type(actions) ~= "table" then
        logging.violate("definition.invalid_field_type", "%s: definition.actions should be table, got %s",
            prefix, type(actions))
    end

    local actionOrder = {}
    for key, handler in pairs(actions) do
        local isInternalAction = IsTrustedInternalAction(key, internalActions)
        if type(key) ~= "string" or key == "" then
            logging.violate("definition.invalid_field_type", "%s: action keys must be non-empty strings", prefix)
        elseif isInternalAction then
            if not IsInternalIdentifier(key) then
                logging.violate("definition.invalid_field_type", "%s: internal action key '%s' %s",
                    prefix, key, InternalIdentifierDescription)
            end
        elseif not IsStableIdentifier(key) then
            logging.violate("definition.invalid_field_type", "%s: action key '%s' %s",
                prefix, key, StableIdentifierDescription)
        end
        if type(handler) ~= "function" then
            logging.violate("definition.invalid_field_type", "%s: actions.%s should be function, got %s",
                prefix, tostring(key), type(handler))
        end
        actionOrder[#actionOrder + 1] = key
    end

    table.sort(actionOrder, CompareStrings)
    definition._actionOrder = actionOrder
end

local function ValidateCacheKey(prefix, name)
    if type(name) ~= "string" or name == "" then
        logging.violate("definition.invalid_field_type", "%s: cache declaration keys must be non-empty strings", prefix)
    elseif not IsStableIdentifier(name) then
        logging.violate("definition.invalid_field_type", "%s: cache declaration key '%s' %s",
            prefix, name, StableIdentifierDescription)
    end
end

local function ValidateCacheString(prefix, path, value)
    if type(value) ~= "string" or value == "" then
        logging.violate("definition.invalid_field_type", "%s: %s must be a non-empty string", prefix, path)
    end
end

local function ValidateKnownCacheKeys(prefix, path, declaration, knownKeys)
    for key in pairs(declaration) do
        if not knownKeys[key] then
            logging.violate("definition.unknown_key", "%s: unknown %s field '%s'", prefix, path, tostring(key))
        end
    end
end

local function PrepareCache(definition, prefix)
    local cache = definition.cache
    if cache == nil then
        definition.cache = {}
        definition._cacheOrder = {}
        return
    end
    if type(cache) ~= "table" then
        logging.violate("definition.invalid_field_type", "%s: definition.cache should be table, got %s",
            prefix, type(cache))
    end

    local cacheOrder = {}
    for name, declaration in pairs(cache) do
        ValidateCacheKey(prefix, name)
        if type(declaration) ~= "table" then
            logging.violate("definition.invalid_field_type", "%s: cache.%s should be table, got %s",
                prefix, tostring(name), type(declaration))
        end

        local path = "cache." .. tostring(name)
        local domain = declaration.domain
        if domain == "currentRun" then
            ValidateKnownCacheKeys(prefix, path, declaration, {
                domain = true,
                key = true,
                factory = true,
            })
            ValidateCacheString(prefix, path .. ".key", declaration.key)
            if declaration.factory ~= nil and type(declaration.factory) ~= "function" then
                logging.violate("definition.invalid_field_type", "%s: %s.factory should be function, got %s",
                    prefix, path, type(declaration.factory))
            end
        else
            logging.violate("definition.invalid_field_type",
                "%s: %s.domain must be 'currentRun'", prefix, path)
        end

        cacheOrder[#cacheOrder + 1] = name
    end

    table.sort(cacheOrder, CompareStrings)
    definition._cacheOrder = cacheOrder
end

local function CompareKeys(a, b)
    local typeA = type(a)
    local typeB = type(b)
    if typeA ~= typeB then
        return typeA < typeB
    end
    if typeA == "number" or typeA == "string" then
        return a < b
    end
    return tostring(a) < tostring(b)
end

local function SerializeStructuralValue(value, seen)
    local valueType = type(value)
    if valueType == "nil" then
        return "nil"
    end
    if valueType == "boolean" then
        return value and "true" or "false"
    end
    if valueType == "number" then
        return string.format("%.17g", value)
    end
    if valueType == "string" then
        return string.format("%q", value)
    end
    if valueType == "function" then
        return "<function>"
    end
    if valueType ~= "table" then
        return "<" .. valueType .. ">"
    end

    seen = seen or {}
    if seen[value] then
        return "<cycle>"
    end
    seen[value] = true

    local keys = {}
    for key in pairs(value) do
        if not (type(key) == "string" and string.sub(key, 1, 1) == "_") then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, CompareKeys)

    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = "[" .. SerializeStructuralValue(key, seen) .. "]="
            .. SerializeStructuralValue(value[key], seen)
    end

    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function GetLabel(definition, fallback)
    if type(fallback) == "string" and fallback ~= "" then
        return fallback
    end
    if type(definition) == "table" then
        local label = definition.name or definition.id
        if type(label) == "string" and label ~= "" then
            return label
        end
    end
    return tostring(plugin and plugin.guid or "module")
end

local function IsLikelyDefinitionTable(definition)
    if type(definition) ~= "table" then
        return false
    end
    for key in pairs(definition) do
        if type(key) == "string" and KnownDefinitionKeys[key] then
            return true
        end
    end
    return false
end

local function ValidateDefinition(definition, label, internalActions)
    if not IsLikelyDefinitionTable(definition) then
        return
    end

    local prefix = GetLabel(definition, label)

    for key in pairs(definition) do
        if type(key) == "string" and not KnownDefinitionKeys[key] then
            logging.violate("definition.unknown_key", "%s: unknown definition key '%s'", prefix, tostring(key))
        end
    end

    local function checkType(key, expected)
        if definition[key] ~= nil and type(definition[key]) ~= expected then
            logging.violate("definition.invalid_field_type", "%s: definition.%s should be %s, got %s",
                prefix, key, expected, type(definition[key]))
        end
    end

    if definition.id == nil or definition.id == "" then
        logging.violate("definition.missing_id", "%s: definition.id is required", prefix)
    elseif type(definition.id) ~= "string" then
        logging.violate("definition.invalid_field_type", "%s: definition.id should be string, got %s",
            prefix, type(definition.id))
    elseif not IsStableIdentifier(definition.id) then
        logging.violate("definition.invalid_field_type", "%s: definition.id '%s' %s",
            prefix, definition.id, StableIdentifierDescription)
    end

    if definition.name == nil or definition.name == "" then
        logging.violate("definition.missing_name", "%s: definition.name is required", prefix)
    elseif type(definition.name) ~= "string" then
        logging.violate("definition.invalid_field_type", "%s: definition.name should be string, got %s",
            prefix, type(definition.name))
    end

    for _, key in ipairs({ "modpack", "shortName", "tooltip" }) do
        checkType(key, "string")
    end
    checkType("storage", "table")
    checkType("cache", "table")
    checkType("actions", "table")
    PrepareCache(definition, prefix)
    PrepareActions(definition, prefix, internalActions)
end

local function GetStructuralFingerprint(definition, structuralSurface)
    local structuralState = {
        modpack = definition and definition.modpack or nil,
        id = definition and definition.id or nil,
        name = definition and definition.name or nil,
        shortName = definition and definition.shortName or nil,
        tooltip = definition and definition.tooltip or nil,
        hasQuickContent = structuralSurface and structuralSurface.hasQuickContent == true or false,
        storage = definition and definition.storage or nil,
        cache = definition and definition.cache or nil,
    }
    return SerializeStructuralValue(structuralState)
end

local function InjectBuiltInStorage(definition, label)
    local systemNodes = {}
    if definition.storage == nil then
        definition.storage = {}
    end
    if type(definition.storage) ~= "table" then
        logging.violate("definition.invalid_args", "%s: definition.storage must be a table", label)
    end

    for _, node in ipairs(definition.storage) do
        if type(node) == "table" and BuiltInStorageAliases[node.alias] then
            logging.violate(
                "definition.reserved_storage_alias",
                "%s: storage alias '%s' is reserved by Lib",
                label,
                tostring(node.alias)
            )
        end
    end

    for index = #BuiltInStorageNodes, 1, -1 do
        local node = values.deepCopy(BuiltInStorageNodes[index])
        systemNodes[node] = true
        table.insert(definition.storage, 1, node)
    end
    return systemNodes
end

local function collectInternalStorageNodes(nodes, internalNodes, prefix)
    if nodes == nil then
        return
    end
    if type(nodes) ~= "table" then
        logging.violate("definition.invalid_field_type", "%s: internal storage must be a table", prefix)
    end

    for index, node in ipairs(nodes) do
        local nodePrefix = prefix .. " storage #" .. index
        if type(node) ~= "table" then
            logging.violate("storage.invalid_node", "%s: storage entry is not a table", nodePrefix)
        end
        local alias = node.alias
        if type(alias) ~= "string" or alias == "" then
            logging.violate("storage.invalid_node", "%s: missing alias", nodePrefix)
        elseif not IsInternalIdentifier(alias) then
            logging.violate("storage.invalid_node", "%s: internal alias '%s' %s",
                nodePrefix, alias, InternalIdentifierDescription)
        end
        internalNodes[node] = true

        if type(node.bits) == "table" then
            for bitIndex, bitNode in ipairs(node.bits) do
                local bitAlias = type(bitNode) == "table" and bitNode.alias or nil
                local bitPrefix = nodePrefix .. " bits[" .. bitIndex .. "]"
                if type(bitAlias) == "string" and bitAlias ~= "" then
                    if not IsInternalIdentifier(bitAlias) then
                        logging.violate("storage.invalid_node", "%s: internal alias '%s' %s",
                            bitPrefix, bitAlias, InternalIdentifierDescription)
                    end
                    internalNodes[bitNode] = true
                end
            end
        end

        if type(node.row) == "table" then
            collectInternalStorageNodes(node.row, internalNodes, nodePrefix .. " row")
        end
    end
end

local function injectInternalStorage(definition, internalStorage, label)
    local internalNodes = {}
    if internalStorage == nil then
        return internalNodes
    end

    if definition.storage == nil then
        definition.storage = {}
    end
    if type(definition.storage) ~= "table" then
        logging.violate("definition.invalid_args", "%s: definition.storage must be a table", label)
    end

    local copied = values.deepCopy(internalStorage)
    collectInternalStorageNodes(copied, internalNodes, label .. " internal")
    for _, node in ipairs(copied) do
        table.insert(definition.storage, node)
    end
    return internalNodes
end

local function injectInternalActions(definition, internalActions, label)
    local internalActionKeys = {}
    if internalActions == nil then
        return internalActionKeys
    end
    if type(internalActions) ~= "table" then
        logging.violate("definition.invalid_field_type", "%s: internal actions must be a table", label)
    end
    if definition.actions == nil then
        definition.actions = {}
    end
    if type(definition.actions) ~= "table" then
        logging.violate("definition.invalid_field_type", "%s: definition.actions should be table, got %s",
            label, type(definition.actions))
    end

    for key, handler in pairs(internalActions) do
        if type(key) ~= "string" or key == "" then
            logging.violate("definition.invalid_field_type", "%s: internal action keys must be non-empty strings", label)
        elseif not IsInternalIdentifier(key) then
            logging.violate("definition.invalid_field_type", "%s: internal action key '%s' %s",
                label, key, InternalIdentifierDescription)
        end
        if definition.actions[key] ~= nil then
            logging.violate("definition.invalid_field_type", "%s: duplicate internal action key '%s'", label, tostring(key))
        end
        definition.actions[key] = handler
        internalActionKeys[key] = true
    end

    return internalActionKeys
end

local function prepareDefinition(structuralState, definition, structuralSurface, internalStorage, internalActions, ...)
    if select("#", ...) ~= 0 then
        logging.violate(
            "definition.invalid_args",
            "prepareDefinition: unexpected extra arguments"
        )
    end
    structuralSurface = NormalizeStructuralSurface(structuralSurface)
    if structuralState ~= nil and type(structuralState) ~= "table" then
        logging.violate("definition.invalid_args", "prepareDefinition: structuralState must be a table when provided")
    end
    if type(definition) ~= "table" then
        logging.violate("definition.invalid_args", "prepareDefinition: definition must be a table")
    end

    local prepared = values.deepCopy(definition)
    local label = GetLabel(prepared)
    local systemNodes = InjectBuiltInStorage(prepared, label)
    local internalNodes = injectInternalStorage(prepared, internalStorage, label)
    local internalActionKeys = injectInternalActions(prepared, internalActions, label)

    ValidateDefinition(prepared, label, internalActionKeys)
    storage.validate(prepared.storage, label, {
        internalNodes = internalNodes,
        systemNodes = systemNodes,
    })

    local fingerprint = GetStructuralFingerprint(prepared, structuralSurface)
    prepared._preparedDefinition = true
    prepared._structuralFingerprint = fingerprint

    if structuralState then
        local previousFingerprint = rawget(structuralState, "_definitionStructuralFingerprint")
        if previousFingerprint ~= nil and previousFingerprint ~= fingerprint then
            structuralState.requiresFullReload = true
            if type(prepared.modpack) == "string" and coordinator.isRegistered(prepared.modpack) then
                moduleRegistry.setPendingCoordinatorRebuild(prepared, {
                    kind = "structural_definition_changed",
                    moduleId = prepared.id,
                    displayName = prepared.name,
                    modpack = prepared.modpack,
                })
            else
                logging.violate("definition.structural_reload_required", "%s: %s", label,
                    "structural definition changed during hot reload; full reload required")
            end
        end
        structuralState._definitionStructuralFingerprint = fingerprint
    end

    return prepared
end

function definitionApi.prepareDefinition(structuralState, definition, structuralSurface, ...)
    return prepareDefinition(structuralState, definition, structuralSurface, nil, nil, ...)
end

function definitionApi.prepareDefinitionWithInternalStorage(
    structuralState,
    definition,
    structuralSurface,
    internalStorage,
    internalActions
)
    return prepareDefinition(structuralState, definition, structuralSurface, internalStorage, internalActions)
end

function definitionApi.prepareDefinitionWithInternalDeclarations(structuralState, definition, structuralSurface, internal)
    internal = internal or {}
    return prepareDefinition(structuralState, definition, structuralSurface, internal.storage, internal.actions)
end

return definitionApi
