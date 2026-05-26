local deps = ...

local logging = deps.logging
local storage = deps.storage
local values = deps.values
local coordinator = deps.coordinator
local hostRegistry = deps.hostRegistry
local plugin = deps.plugin

local definitionService = {}

local KnownDefinitionKeys = {
    modpack = true,
    id = true,
    name = true,
    shortName = true,
    tooltip = true,
    storage = true,
    cache = true,
    actions = true,
    hashGroupPlan = true,
}

local KnownHashGroupKeys = {
    keyPrefix = true,
    items = true,
}

local BuiltInStorageNodes = {
    { type = "bool", alias = "Enabled", default = false },
    { type = "bool", alias = "DebugMode", default = false, hash = false },
    {
        type = "int",
        alias = "AdamantFramework_PackRestoreSnapshot",
        default = 0,
        min = 0,
        max = 2,
        hash = false,
    },
}

local BuiltInStorageAliases = {
    Enabled = true,
    DebugMode = true,
    AdamantFramework_PackRestoreSnapshot = true,
}

local StableIdentifierPattern = "^[A-Za-z][A-Za-z0-9_]*$"
local StableIdentifierDescription = "must start with a letter and contain only letters, digits, and underscores"


local KnownStructuralSurfaceKeys = {
    hasQuickContent = true,
}

local function IsStableIdentifier(value)
    return type(value) == "string" and string.match(value, StableIdentifierPattern) ~= nil
end

local function ValidateListShape(value, prefix, path)
    local count = 0
    local maxIndex = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or math.floor(key) ~= key then
            logging.violate("definition.invalid_field_type", "%s: %s must be a list", prefix, path)
        end
        count = count + 1
        if key > maxIndex then
            maxIndex = key
        end
    end
    if count ~= maxIndex then
        logging.violate("definition.invalid_field_type", "%s: %s must be a contiguous list", prefix, path)
    end
end

local function NormalizeStructuralSurface(surface)
    if surface == nil then
        return nil
    end
    if type(surface) ~= "table" then
        logging.violate(
            "definition.invalid_args",
            "prepareDefinition: pass storage defaults on definition.storage nodes, not as a separate argument"
        )
    end

    local hasKnownKey = false
    for key in pairs(surface) do
        if KnownStructuralSurfaceKeys[key] then
            hasKnownKey = true
        end
    end

    if not hasKnownKey and next(surface) ~= nil then
        logging.violate(
            "definition.invalid_args",
            "prepareDefinition: pass storage defaults on definition.storage nodes, not as a separate argument"
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

local function PrepareActions(definition, prefix)
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
        if type(key) ~= "string" or key == "" then
            logging.violate("definition.invalid_field_type", "%s: action keys must be non-empty strings", prefix)
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

local function ValidateHashGroupPlan(definition, prefix)
    local hashGroupPlan = definition.hashGroupPlan
    if hashGroupPlan == nil then
        return
    end
    if type(hashGroupPlan) ~= "table" then
        return
    end

    ValidateListShape(hashGroupPlan, prefix, "hashGroupPlan")
    local seenPrefixes = {}

    for groupIndex, group in ipairs(hashGroupPlan) do
        if type(group) ~= "table" then
            logging.violate(
                "definition.invalid_field_type",
                "%s: hashGroupPlan[%d] must be table",
                prefix,
                groupIndex
            )
        end

        for key in pairs(group) do
            if not KnownHashGroupKeys[key] then
                logging.violate(
                    "definition.unknown_key",
                    "%s: unknown hashGroupPlan[%d] field '%s'",
                    prefix,
                    groupIndex,
                    tostring(key)
                )
            end
        end

        local keyPrefix = group.keyPrefix
        if type(keyPrefix) ~= "string" or keyPrefix == "" then
            logging.violate(
                "definition.invalid_field_type",
                "%s: hashGroupPlan[%d].keyPrefix is required",
                prefix,
                groupIndex
            )
        elseif not IsStableIdentifier(keyPrefix) then
            logging.violate(
                "definition.invalid_field_type",
                "%s: hashGroupPlan[%d].keyPrefix '%s' %s",
                prefix,
                groupIndex,
                keyPrefix,
                StableIdentifierDescription
            )
        end

        if seenPrefixes[keyPrefix] then
            logging.violate(
                "definition.invalid_field_type",
                "%s: duplicate hashGroupPlan keyPrefix '%s'",
                prefix,
                keyPrefix
            )
        end
        seenPrefixes[keyPrefix] = true

        if type(group.items) ~= "table" then
            logging.violate(
                "definition.invalid_field_type",
                "%s: hashGroupPlan[%d].items is required",
                prefix,
                groupIndex
            )
        end
        ValidateListShape(group.items, prefix, string.format("hashGroupPlan[%d].items", groupIndex))
        if #group.items == 0 then
            logging.violate(
                "definition.invalid_field_type",
                "%s: hashGroupPlan[%d].items must contain at least one item",
                prefix,
                groupIndex
            )
        end

        for itemIndex, item in ipairs(group.items) do
            if type(item) == "string" then
                if item == "" then
                    logging.violate(
                        "definition.invalid_field_type",
                        "%s: hashGroupPlan[%d].items[%d] must be a non-empty alias string",
                        prefix,
                        groupIndex,
                        itemIndex
                    )
                end
            elseif type(item) == "table" then
                local itemPath = string.format("hashGroupPlan[%d].items[%d]", groupIndex, itemIndex)
                ValidateListShape(item, prefix, itemPath)
                if #item == 0 then
                    logging.violate(
                        "definition.invalid_field_type",
                        "%s: %s must contain at least one alias",
                        prefix,
                        itemPath
                    )
                end
                for aliasIndex, alias in ipairs(item) do
                    if type(alias) ~= "string" or alias == "" then
                        logging.violate(
                            "definition.invalid_field_type",
                            "%s: %s[%d] must be a non-empty alias string",
                            prefix,
                            itemPath,
                            aliasIndex
                        )
                    end
                end
            else
                logging.violate(
                    "definition.invalid_field_type",
                    "%s: hashGroupPlan[%d].items[%d] must be an alias string or alias list",
                    prefix,
                    groupIndex,
                    itemIndex
                )
            end
        end
    end
end

local function GetHashGroupPackWidth(node)
    local storageType = node and node.type and storage.types[node.type] or nil
    if storageType and storageType.packWidth ~= nil then
        return storageType.packWidth(node)
    end
    return nil
end

local function ValidateHashGroupAlias(aliasNodes, alias, prefix, path)
    if alias == "Enabled" then
        logging.violate(
            "definition.invalid_field_type",
            "%s: %s alias '%s' is encoded as module enable state; storage groups cannot include it",
            prefix,
            path,
            alias
        )
    end

    local node = aliasNodes[alias]
    if not node then
        logging.violate(
            "definition.invalid_field_type",
            "%s: %s references unknown storage alias '%s'",
            prefix,
            path,
            alias
        )
    end
    if node._isBitAlias then
        logging.violate(
            "definition.invalid_field_type",
            "%s: %s alias '%s' is a packed child alias; only root storage aliases are supported",
            prefix,
            path,
            alias
        )
    end
    if node._hash ~= true then
        logging.violate(
            "definition.invalid_field_type",
            "%s: %s alias '%s' is excluded from hashes; only hash root aliases are supported",
            prefix,
            path,
            alias
        )
    end

    local width = GetHashGroupPackWidth(node)
    if not width then
        logging.violate(
            "definition.invalid_field_type",
            "%s: %s alias '%s' cannot be packed",
            prefix,
            path,
            alias
        )
    end
    return width
end

local function RecordHashGroupAlias(seenAliases, alias, prefix, path)
    local existingPath = seenAliases[alias]
    if existingPath then
        logging.violate(
            "definition.invalid_field_type",
            "%s: duplicate hashGroupPlan alias '%s' at %s; first used at %s",
            prefix,
            alias,
            path,
            existingPath
        )
    end
    seenAliases[alias] = path
end

local function ValidatePreparedHashGroupPlan(definition, prefix)
    local hashGroupPlan = definition.hashGroupPlan
    if hashGroupPlan == nil then
        return
    end

    local aliasNodes = storage.getAliases(definition.storage)
    local seenAliases = {}
    for groupIndex, group in ipairs(hashGroupPlan) do
        for itemIndex, item in ipairs(group.items) do
            local itemWidth = 0
            if type(item) == "string" then
                local path = string.format("hashGroupPlan[%d].items[%d]", groupIndex, itemIndex)
                itemWidth = ValidateHashGroupAlias(
                    aliasNodes,
                    item,
                    prefix,
                    path
                )
                RecordHashGroupAlias(seenAliases, item, prefix, path)
            else
                for aliasIndex, alias in ipairs(item) do
                    local path = string.format("hashGroupPlan[%d].items[%d][%d]", groupIndex, itemIndex, aliasIndex)
                    itemWidth = itemWidth + ValidateHashGroupAlias(
                        aliasNodes,
                        alias,
                        prefix,
                        path
                    )
                    RecordHashGroupAlias(seenAliases, alias, prefix, path)
                end
            end

            if itemWidth > 32 then
                logging.violate(
                    "definition.invalid_field_type",
                    "%s: hashGroupPlan[%d].items[%d] exceeds 32 packed bits",
                    prefix,
                    groupIndex,
                    itemIndex
                )
            end
        end
    end
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

local function ValidateDefinition(definition, label)
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
    checkType("hashGroupPlan", "table")
    PrepareCache(definition, prefix)
    PrepareActions(definition, prefix)
    ValidateHashGroupPlan(definition, prefix)
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
        hashGroupPlan = definition and definition.hashGroupPlan or nil,
    }
    return SerializeStructuralValue(structuralState)
end

local function InjectBuiltInStorage(definition, label)
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
        table.insert(definition.storage, 1, values.deepCopy(BuiltInStorageNodes[index]))
    end
end

function definitionService.prepareDefinition(structuralState, definition, structuralSurface, ...)
    if select("#", ...) ~= 0 then
        logging.violate(
            "definition.invalid_args",
            "prepareDefinition: pass storage defaults on definition.storage nodes, not as a separate argument"
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
    InjectBuiltInStorage(prepared, label)

    ValidateDefinition(prepared, label)
    storage.validate(prepared.storage, label)
    ValidatePreparedHashGroupPlan(prepared, label)

    local fingerprint = GetStructuralFingerprint(prepared, structuralSurface)
    prepared._preparedDefinition = true
    prepared._structuralFingerprint = fingerprint

    if structuralState then
        local previousFingerprint = rawget(structuralState, "_definitionStructuralFingerprint")
        if previousFingerprint ~= nil and previousFingerprint ~= fingerprint then
            structuralState.requiresFullReload = true
            if type(prepared.modpack) == "string" and coordinator.isRegistered(prepared.modpack) then
                hostRegistry.setPendingCoordinatorRebuild(prepared, {
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

return definitionService
