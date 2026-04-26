local internal = AdamantModpackLib_Internal
internal.definition = internal.definition or {}
local definitionInternal = internal.definition
local storageInternal = internal.storage
local mutationInternal = internal.mutation

local KnownDefinitionKeys = {
    modpack = true,
    id = true,
    name = true,
    shortName = true,
    tooltip = true,
    affectsRunData = true,
    storage = true,
    hashGroupPlan = true,
    patchPlan = true,
    apply = true,
    revert = true,
}

definitionInternal.KnownKeys = KnownDefinitionKeys

local function DeepCopyValue(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[DeepCopyValue(key, seen)] = DeepCopyValue(child, seen)
    end
    return copy
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

function definitionInternal.getLabel(definition, fallback)
    if type(fallback) == "string" and fallback ~= "" then
        return fallback
    end
    if type(definition) == "table" then
        local label = definition.name or definition.id
        if type(label) == "string" and label ~= "" then
            return label
        end
    end
    return tostring(_PLUGIN.guid or "module")
end

function definitionInternal.isPrepared(definition)
    return type(definition) == "table" and rawget(definition, "_preparedDefinition") == true
end

function definitionInternal.isLikelyDefinitionTable(definition)
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

function definitionInternal.validate(definition, label)
    if not definitionInternal.isLikelyDefinitionTable(definition) then
        return
    end

    local warn = internal.logging.warn
    local prefix = definitionInternal.getLabel(definition, label)

    for key in pairs(definition) do
        if type(key) == "string" and not KnownDefinitionKeys[key] then
            warn("%s: unknown definition key '%s'", prefix, tostring(key))
        end
    end

    local function warnType(key, expected)
        if definition[key] ~= nil and type(definition[key]) ~= expected then
            warn("%s: definition.%s should be %s, got %s",
                prefix, key, expected, type(definition[key]))
        end
    end

    for _, key in ipairs({ "modpack", "id", "name", "shortName", "tooltip" }) do
        warnType(key, "string")
    end
    warnType("affectsRunData", "boolean")
    warnType("storage", "table")
    warnType("hashGroupPlan", "table")
    for _, key in ipairs({ "patchPlan", "apply", "revert" }) do
        warnType(key, "function")
    end

    if definition.modpack ~= nil and definition.id == nil then
        warn("%s: coordinated modules should declare definition.id", prefix)
    end

    local inferred, info = mutationInternal.inferMutation(definition)
    if info.hasApply ~= info.hasRevert then
        warn("%s: manual lifecycle requires both definition.apply and definition.revert", prefix)
    end
    if mutationInternal.mutatesRunData(definition) and not inferred then
        warn("%s: affectsRunData=true but module exposes neither patchPlan nor apply/revert", prefix)
    end
end

function definitionInternal.getStructuralFingerprint(definition)
    local structuralState = {
        modpack = definition and definition.modpack or nil,
        id = definition and definition.id or nil,
        name = definition and definition.name or nil,
        shortName = definition and definition.shortName or nil,
        affectsRunData = definition and definition.affectsRunData or nil,
        storage = definition and definition.storage or nil,
        hashGroupPlan = definition and definition.hashGroupPlan or nil,
    }
    return SerializeStructuralValue(structuralState)
end

function definitionInternal.prepare(owner, dataDefaultsOrDefinition, definitionOrNil)
    assert(owner == nil or type(owner) == "table",
        "prepareDefinition: owner must be a table when provided")
    local dataDefaults = nil
    local definition = dataDefaultsOrDefinition
    if definitionOrNil ~= nil then
        dataDefaults = dataDefaultsOrDefinition
        definition = definitionOrNil
    end
    assert(type(definition) == "table", "prepareDefinition: definition must be a table")

    local prepared = DeepCopyValue(definition)
    local label = definitionInternal.getLabel(prepared)

    if type(prepared.storage) == "table" then
        storageInternal.hydrateDefaults(prepared.storage, dataDefaults)
    end

    if internal.libConfig.DebugMode == true then
        definitionInternal.validate(prepared, label)
    end
    if type(prepared.storage) == "table" then
        storageInternal.validate(prepared.storage, label)
    end

    local fingerprint = definitionInternal.getStructuralFingerprint(prepared)
    prepared._preparedDefinition = true
    prepared._structuralFingerprint = fingerprint

    if owner then
        local previousFingerprint = rawget(owner, "_definitionStructuralFingerprint")
        if previousFingerprint ~= nil and previousFingerprint ~= fingerprint then
            owner.requiresFullReload = true
            if type(prepared.modpack) == "string" and public.isModuleCoordinated(prepared.modpack) then
                prepared._pendingCoordinatorRebuildReason = {
                    kind = "structural_definition_changed",
                    moduleId = prepared.id,
                    moduleName = prepared.name,
                    modpack = prepared.modpack,
                }
            else
                public.logging.warn(label,
                    "structural definition changed during hot reload; full reload required")
            end
        end
        owner._definitionStructuralFingerprint = fingerprint
    end

    return prepared
end

function public.prepareDefinition(owner, dataDefaultsOrDefinition, definitionOrNil)
    return definitionInternal.prepare(owner, dataDefaultsOrDefinition, definitionOrNil)
end
