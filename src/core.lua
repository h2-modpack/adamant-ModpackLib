local internal = AdamantModpackLib_Internal
local shared = internal.shared
local libConfig = shared.libConfig
local StorageTypes = shared.StorageTypes
local _coordinators = shared.coordinators
local chalk = shared.chalk
local _mutationRuntime = shared.mutationRuntime or setmetatable({}, { __mode = "k" })
shared.mutationRuntime = _mutationRuntime

local function StorageKey(key)
    local helper = shared.StorageKey
    if type(helper) == "function" then
        return helper(key)
    end
    if type(key) == "table" then
        return table.concat(key, ".")
    end
    return tostring(key)
end

function public.registerCoordinator(packId, config)
    _coordinators[packId] = config
end

function public.isCoordinated(packId)
    return _coordinators[packId] ~= nil
end

function public.isEnabled(store, packId)
    local coord = packId and _coordinators[packId]
    if coord and not coord.ModEnabled then return false end
    return store and type(store.read) == "function" and store.read("Enabled") == true or false
end

local function FormatWarning(prefix, fmt, ...)
    return prefix .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt)
end

local function libWarn(fmt, ...)
    if not libConfig.DebugMode then return end
    print(FormatWarning("[lib] ", fmt, ...))
end
shared.libWarn = libWarn

local function libWarnAlways(fmt, ...)
    print(FormatWarning("[lib] ", fmt, ...))
end
shared.libWarnAlways = libWarnAlways

function public.warn(packId, enabled, fmt, ...)
    if not enabled then return end
    print(FormatWarning("[" .. packId .. "] ", fmt, ...))
end

function public.contractWarn(packId, fmt, ...)
    print(FormatWarning("[" .. packId .. "] ", fmt, ...))
end

function public.log(name, enabled, fmt, ...)
    if not enabled then return end
    print("[" .. name .. "] " .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt))
end

local function CloneMutationValue(value)
    if type(value) == "table" then
        return rom.game.DeepCopyTable(value)
    end
    return value
end

local function DeepValueEqual(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end

    for key, value in pairs(a) do
        if not DeepValueEqual(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

local MutationDeepEqual = DeepValueEqual

function public.createBackupSystem()
    local NIL = {}
    local savedValues = {}

    local function backup(tbl, ...)
        savedValues[tbl] = savedValues[tbl] or {}
        local saved = savedValues[tbl]
        for i = 1, select("#", ...) do
            local key = select(i, ...)
            if saved[key] == nil then
                local v = tbl[key]
                saved[key] = (v == nil) and NIL or (type(v) == "table" and rom.game.DeepCopyTable(v) or v)
            end
        end
    end

    local function restore()
        for tbl, keys in pairs(savedValues) do
            for key, v in pairs(keys) do
                if v == NIL then
                    tbl[key] = nil
                elseif type(v) == "table" then
                    tbl[key] = rom.game.DeepCopyTable(v)
                else
                    tbl[key] = v
                end
            end
        end
    end

    return backup, restore
end

function public.createMutationPlan()
    local backup, restore = public.createBackupSystem()
    local operations = {}
    local applied = false
    local plan = {}

    local function appendOperation(op)
        operations[#operations + 1] = op
        return plan
    end

    function plan.set(_, tbl, key, value)
        return appendOperation({
            kind = "set",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
        })
    end

    function plan.setMany(_, tbl, kv)
        return appendOperation({
            kind = "setMany",
            tbl = tbl,
            kv = kv,
        })
    end

    function plan.transform(_, tbl, key, fn)
        return appendOperation({
            kind = "transform",
            tbl = tbl,
            key = key,
            fn = fn,
        })
    end

    function plan.append(_, tbl, key, value)
        return appendOperation({
            kind = "append",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
        })
    end

    function plan.appendUnique(_, tbl, key, value, equivalentFn)
        return appendOperation({
            kind = "appendUnique",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
            equivalentFn = equivalentFn or MutationDeepEqual,
        })
    end

    function plan.removeElement(_, tbl, key, value, equivalentFn)
        return appendOperation({
            kind = "removeElement",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
            equivalentFn = equivalentFn or MutationDeepEqual,
        })
    end

    function plan.setElement(_, tbl, key, oldValue, newValue, equivalentFn)
        return appendOperation({
            kind = "setElement",
            tbl = tbl,
            key = key,
            oldValue = CloneMutationValue(oldValue),
            newValue = CloneMutationValue(newValue),
            equivalentFn = equivalentFn or MutationDeepEqual,
        })
    end

    function plan.apply()
        if applied then
            return false
        end

        for _, op in ipairs(operations) do
            local tbl = op.tbl
            local key = op.key

            if op.kind == "set" then
                if tbl[key] ~= op.value then
                    backup(tbl, key)
                    tbl[key] = CloneMutationValue(op.value)
                end
            elseif op.kind == "setMany" then
                for mapKey, value in pairs(op.kv) do
                    if tbl[mapKey] ~= value then
                        backup(tbl, mapKey)
                        tbl[mapKey] = CloneMutationValue(value)
                    end
                end
            elseif op.kind == "transform" then
                backup(tbl, key)
                tbl[key] = op.fn(tbl[key], key, tbl)
            elseif op.kind == "append" then
                local list = tbl[key]
                if list == nil then
                    backup(tbl, key)
                    list = {}
                    tbl[key] = list
                elseif type(list) ~= "table" then
                    error(("mutation plan append requires table at key '%s'"):format(tostring(key)), 0)
                else
                    backup(tbl, key)
                end
                list[#list + 1] = CloneMutationValue(op.value)
            elseif op.kind == "appendUnique" then
                local list = tbl[key]
                if list == nil then
                    backup(tbl, key)
                    list = {}
                    tbl[key] = list
                elseif type(list) ~= "table" then
                    error(("mutation plan appendUnique requires table at key '%s'"):format(tostring(key)), 0)
                end

                local exists = false
                for _, entry in ipairs(list) do
                    if op.equivalentFn(entry, op.value) then
                        exists = true
                        break
                    end
                end
                if not exists then
                    backup(tbl, key)
                    list[#list + 1] = CloneMutationValue(op.value)
                end
            elseif op.kind == "removeElement" then
                local list = tbl[key]
                if type(list) == "table" then
                    for index, entry in ipairs(list) do
                        if op.equivalentFn(entry, op.value) then
                            backup(tbl, key)
                            table.remove(list, index)
                            break
                        end
                    end
                elseif list ~= nil then
                    error(("mutation plan removeElement requires table at key '%s'"):format(tostring(key)), 0)
                end

            elseif op.kind == "setElement" then
                local list = tbl[key]
                if type(list) == "table" then
                    for index, entry in ipairs(list) do
                        if op.equivalentFn(entry, op.oldValue) then
                            backup(tbl, key)
                            list[index] = CloneMutationValue(op.newValue)
                            break
                        end
                    end
                elseif list ~= nil then
                    error(("mutation plan setElement requires table at key '%s'"):format(tostring(key)), 0)
                end
            end
        end

        applied = true
        return true
    end

    function plan.revert()
        if not applied then
            return false
        end
        restore()
        applied = false
        return true
    end

    return plan
end

function public.inferMutationShape(def)
    local hasPatch = def and type(def.patchPlan) == "function" or false
    local hasApply = def and type(def.apply) == "function" or false
    local hasRevert = def and type(def.revert) == "function" or false
    local hasManual = hasApply and hasRevert

    local inferred = nil
    if hasPatch and hasManual then
        inferred = "hybrid"
    elseif hasPatch then
        inferred = "patch"
    elseif hasManual then
        inferred = "manual"
    end

    return inferred, {
        hasPatch = hasPatch,
        hasApply = hasApply,
        hasRevert = hasRevert,
        hasManual = hasManual,
    }
end

function public.affectsRunData(def)
    if not def then
        return false
    end
    return def.affectsRunData == true
end

local KnownDefinitionKeys = {
    modpack = true,
    id = true,
    name = true,
    shortName = true,
    special = true,
    category = true,
    subgroup = true,
    tooltip = true,
    default = true,
    affectsRunData = true,
    storage = true,
    ui = true,
    customTypes = true,
    patchPlan = true,
    apply = true,
    revert = true,
    selectQuickUi = true,
    hashGroups = true,
}

local function IsLikelyDefinitionTable(def)
    if type(def) ~= "table" then
        return false
    end

    if def.stateSchema ~= nil or def.options ~= nil then
        return true
    end

    for key in pairs(def) do
        if type(key) == "string" and KnownDefinitionKeys[key] then
            return true
        end
    end

    return false
end

function public.validateDefinition(def, label)
    if not IsLikelyDefinitionTable(def) then
        return def
    end

    local prefix = tostring(label or def.name or def.id or _PLUGIN.guid or "module")

    for key in pairs(def) do
        if type(key) == "string"
            and key ~= "stateSchema"
            and key ~= "options"
            and not KnownDefinitionKeys[key] then
            libWarnAlways("%s: unknown definition key '%s'", prefix, tostring(key))
        end
    end

    local function warnType(key, expected)
        if def[key] ~= nil and type(def[key]) ~= expected then
            libWarnAlways("%s: definition.%s should be %s, got %s",
                prefix, key, expected, type(def[key]))
        end
    end

    for _, key in ipairs({ "modpack", "id", "name", "shortName", "category", "subgroup", "tooltip" }) do
        warnType(key, "string")
    end
    -- Discovery accepts any default value type; do not type-check it.
    for _, key in ipairs({ "special", "affectsRunData" }) do
        warnType(key, "boolean")
    end
    for _, key in ipairs({ "storage", "ui", "customTypes", "hashGroups" }) do
        warnType(key, "table")
    end
    for _, key in ipairs({ "patchPlan", "apply", "revert", "selectQuickUi" }) do
        warnType(key, "function")
    end

    if def.special == true then
        if def.category ~= nil then
            libWarnAlways("%s: special modules ignore definition.category", prefix)
        end
        if def.subgroup ~= nil then
            libWarnAlways("%s: special modules ignore definition.subgroup", prefix)
        end
        if def.selectQuickUi ~= nil then
            libWarnAlways("%s: special modules ignore definition.selectQuickUi; use DrawQuickContent for Quick Setup", prefix)
        end
        if def.modpack ~= nil and def.name == nil then
            libWarnAlways("%s: coordinated special modules should declare definition.name", prefix)
        end
    else
        if def.shortName ~= nil then
            libWarnAlways("%s: regular modules ignore definition.shortName", prefix)
        end
        if def.modpack ~= nil and def.id == nil then
            libWarnAlways("%s: coordinated regular modules should declare definition.id", prefix)
        end
    end

    local inferred, info = public.inferMutationShape(def)
    if info.hasApply ~= info.hasRevert then
        libWarnAlways("%s: manual lifecycle requires both definition.apply and definition.revert", prefix)
    end
    if public.affectsRunData(def) and not inferred then
        libWarnAlways("%s: affectsRunData=true but module exposes neither patchPlan nor apply/revert", prefix)
    end

    return def
end

function public.valuesEqual(node, a, b)
    local storageType = node and StorageTypes and node.type and StorageTypes[node.type] or nil
    if storageType and type(storageType.equals) == "function" then
        return storageType.equals(node, a, b)
    end
    return DeepValueEqual(a, b)
end

local function GetActiveMutationPlan(store)
    local runtime = store and _mutationRuntime[store]
    return runtime and runtime.plan or nil
end

local function SetActiveMutationPlan(store, plan)
    if not store then
        return
    end
    if plan == nil then
        _mutationRuntime[store] = nil
        return
    end
    _mutationRuntime[store] = { plan = plan }
end

local function BuildMutationPlan(def, store)
    local builder = def and def.patchPlan
    if type(builder) ~= "function" then
        return nil
    end

    local plan = public.createMutationPlan()
    builder(plan, store)
    return plan
end

function public.applyDefinition(def, store)
    local inferred, info = public.inferMutationShape(def)
    if not inferred then
        if not public.affectsRunData(def) then
            return true, nil
        end
        return false, "no supported mutation lifecycle found"
    end

    local activePlan = GetActiveMutationPlan(store)
    if activePlan then
        local okRevert, errRevert = pcall(activePlan.revert, activePlan)
        if not okRevert then
            return false, errRevert
        end
        SetActiveMutationPlan(store, nil)
    end

    local builtPlan = nil
    if info.hasPatch then
        local okBuild, result = pcall(BuildMutationPlan, def, store)
        if not okBuild then
            return false, result
        end
        builtPlan = result
        if builtPlan then
            local okApply, errApply = pcall(builtPlan.apply, builtPlan)
            if not okApply then
                return false, errApply
            end
            SetActiveMutationPlan(store, builtPlan)
        end
    end

    if info.hasManual then
        local okManual, errManual = pcall(def.apply)
        if not okManual then
            if builtPlan then
                pcall(builtPlan.revert, builtPlan)
                SetActiveMutationPlan(store, nil)
            end
            return false, errManual
        end
    end

    return true, nil
end

function public.revertDefinition(def, store)
    local inferred, info = public.inferMutationShape(def)
    if not inferred then
        if not public.affectsRunData(def) then
            return true, nil
        end
        return false, "no supported mutation lifecycle found"
    end

    local firstErr = nil

    if info.hasManual then
        local okManual, errManual = pcall(def.revert)
        if not okManual and not firstErr then
            firstErr = errManual
        end
    end

    local activePlan = GetActiveMutationPlan(store)
    if activePlan then
        local okPlan, errPlan = pcall(activePlan.revert, activePlan)
        SetActiveMutationPlan(store, nil)
        if not okPlan and not firstErr then
            firstErr = errPlan
        end
    end

    if firstErr then
        return false, firstErr
    end

    return true, nil
end

function public.setDefinitionEnabled(def, store, enabled)
    local current = store and type(store.read) == "function" and store.read("Enabled") == true or false

    local ok, err
    if enabled and current then
        ok, err = public.reapplyDefinition(def, store)
    elseif enabled then
        ok, err = public.applyDefinition(def, store)
    elseif current then
        ok, err = public.revertDefinition(def, store)
    else
        ok, err = true, nil
    end

    if not ok then
        return false, err
    end

    store.write("Enabled", enabled)
    return true, nil
end

function public.reapplyDefinition(def, store)
    local okRevert, errRevert = public.revertDefinition(def, store)
    if not okRevert then
        return false, errRevert
    end

    local okApply, errApply = public.applyDefinition(def, store)
    if not okApply then
        return false, errApply
    end

    return true, nil
end

local function BuildManagedStorage(definition)
    if type(definition) ~= "table" then
        return nil
    end

    if definition.stateSchema ~= nil or definition.options ~= nil then
        error("legacy definition.stateSchema/options are no longer supported; use definition.storage and definition.ui", 2)
    end

    if definition.storage ~= nil
        or definition.ui ~= nil
        or definition.special ~= nil
        or definition.id ~= nil
    then
        local label = tostring(definition.name or definition.id or _PLUGIN.guid or "module")
        if type(definition.storage) == "table" then
            return definition.storage
        end
        if type(definition.ui) == "table" and #definition.ui > 0 then
            libWarnAlways("%s: module declares definition.ui but missing definition.storage; no uiState created", label)
        end
        return nil
    end

    if #definition > 0 then
        error("createStore expects a module definition table; raw storage/ui arrays are not supported", 2)
    end
    return nil
end

function public.standaloneUI(def, store)
    local function TrySetEnabled(enabled)
        local ok, err = public.setDefinitionEnabled(def, store, enabled)
        if ok then
            if public.affectsRunData(def) then rom.game.SetupRunData() end
        else
            libWarnAlways("%s %s failed: %s",
                tostring(def.name or def.id or "module"),
                enabled and "enable" or "disable",
                tostring(err))
        end
        return ok, err
    end

    local function onUiStateFlushed()
        if public.affectsRunData(def) and store.read("Enabled") == true then
            rom.game.SetupRunData()
        end
    end

    return function()
        if def.modpack and _coordinators[def.modpack] then return end
        if rom.ImGui.BeginMenu(def.name) then
            local imgui = rom.ImGui
            local enabled = store.read("Enabled") == true
            local val, chg = imgui.Checkbox(def.name, enabled)
            if chg then
                TrySetEnabled(val)
            end
            if imgui.IsItemHovered() and (def.tooltip or "") ~= "" then
                imgui.SetTooltip(def.tooltip)
            end

            local dbgVal, dbgChg = imgui.Checkbox("Debug Mode", store.read("DebugMode") == true)
            if dbgChg then
                store.write("DebugMode", dbgVal)
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip("Print diagnostic warnings to the console for this module.")
            end

            if store.uiState and imgui.Button("Audit + Resync UI State") then
                public.auditAndResyncUiState(def.name or def.id or "module", store.uiState)
            end

            if enabled and store.uiState and type(def.ui) == "table" and #def.ui > 0 then
                imgui.Separator()
                public.runUiStatePass({
                    name = def.name,
                    imgui = imgui,
                    uiState = store.uiState,
                    commit = function(state)
                        return public.commitUiState(def, store, state)
                    end,
                    draw = function()
                        public.drawUiTree(imgui, def.ui, store.uiState, imgui.GetWindowWidth() * 0.45, def.customTypes)
                    end,
                    onFlushed = onUiStateFlushed,
                })
            end

            imgui.EndMenu()
        end
    end
end

function public.readPath(tbl, key)
    if type(key) == "table" then
        if #key == 0 then return nil, nil, nil end
        for i = 1, #key - 1 do
            tbl = tbl[key[i]]
            if not tbl then return nil, nil, nil end
        end
        return tbl[key[#key]], tbl, key[#key]
    end
    return tbl[key], tbl, key
end

function public.writePath(tbl, key, value)
    if type(key) == "table" then
        for i = 1, #key - 1 do
            tbl[key[i]] = tbl[key[i]] or {}
            tbl = tbl[key[i]]
        end
        tbl[key[#key]] = value
        return
    end
    tbl[key] = value
end

local function GetBitValueMask(width)
    local normalizedWidth = math.floor(tonumber(width) or 0)
    if normalizedWidth <= 0 then
        return 0
    end
    if normalizedWidth >= 32 then
        return 0xFFFFFFFF
    end
    return bit32.rshift(0xFFFFFFFF, 32 - normalizedWidth)
end

function public.readBitsValue(packed, offset, width)
    local normalizedPacked = math.floor(tonumber(packed) or 0)
    local normalizedOffset = math.max(0, math.floor(tonumber(offset) or 0))
    local mask = GetBitValueMask(width)
    if mask == 0 then
        return 0
    end
    return bit32.band(bit32.rshift(normalizedPacked, normalizedOffset), mask)
end

function public.writeBitsValue(packed, offset, width, value)
    local normalizedPacked = math.floor(tonumber(packed) or 0)
    local normalizedOffset = math.max(0, math.floor(tonumber(offset) or 0))
    local mask = GetBitValueMask(width)
    if mask == 0 then
        return normalizedPacked
    end

    local normalizedValue = math.floor(tonumber(value) or 0)
    if normalizedValue < 0 then
        normalizedValue = 0
    elseif normalizedValue > mask then
        normalizedValue = mask
    end

    local shiftedMask = bit32.lshift(mask, normalizedOffset)
    local cleared = bit32.band(normalizedPacked, bit32.bnot(shiftedMask))
    return bit32.bor(cleared, bit32.lshift(normalizedValue, normalizedOffset))
end

local function NormalizeStorageValue(node, value)
    local storageType = node and node.type and StorageTypes[node.type] or nil
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
        local pathKey = StorageKey(configKey)
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
shared.GetConfigBackend = GetConfigBackend

function public.createStore(modConfig, definition, dataDefaults)
    local backend = GetConfigBackend(modConfig)
    local store = {}
    local storage = BuildManagedStorage(definition)

    if storage and type(dataDefaults) == "table" then
        for _, node in ipairs(storage) do
            if node.default == nil then
                local key = node.configKey or node.alias
                if key ~= nil then
                    node.default = public.readPath(dataDefaults, key)
                end
            end
        end
    end
    local label = type(definition) == "table"
        and tostring(definition.name or definition.id or _PLUGIN.guid or "module")
        or tostring(_PLUGIN.guid or "module")

    if type(definition) == "table" then
        public.validateDefinition(definition, label)
    end

    if storage then
        public.validateStorage(storage, label)
        if type(definition.ui) == "table" then
            public.validateUi(definition.ui, label, storage, definition.customTypes)
        end
    elseif type(definition) == "table" and type(definition.ui) == "table" and #definition.ui > 0 then
        libWarnAlways("%s: definition.ui declared without definition.storage; UI state disabled", label)
    end

    local aliasNodes = storage and public.getStorageAliases(storage) or {}
    local rootByKey = storage and (rawget(storage, "_rootByKey") or {}) or {}

    local function readRaw(configKey)
        local raw
        if backend then
            raw = backend.readValue(configKey)
        end
        if raw == nil then
            raw = public.readPath(modConfig, configKey)
        end
        return raw
    end

    local function writeRaw(configKey, value)
        if backend and backend.writeValue(configKey, value) then
            return
        end
        public.writePath(modConfig, configKey, value)
    end

    local function readRootNode(root)
        local raw = readRaw(root.configKey)
        if raw == nil then
            raw = CloneMutationValue(root.default)
        end
        return NormalizeStorageValue(root, raw)
    end

    local function writeRootNode(root, value)
        writeRaw(root.configKey, NormalizeStorageValue(root, value))
    end

    function store.read(keyOrAlias)
        if type(keyOrAlias) == "string" then
            local node = aliasNodes[keyOrAlias]
            if node then
                if node._isBitAlias then
                    local packed = readRootNode(node.parent)
                    local rawValue = public.readBitsValue(packed, node.offset, node.width)
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

    function store.write(keyOrAlias, value)
        if type(keyOrAlias) == "string" then
            local node = aliasNodes[keyOrAlias]
            if node then
                if node._isBitAlias then
                    local parent = node.parent
                    local currentPacked = readRootNode(parent)
                    local normalized = NormalizeStorageValue(node, value)
                    local encoded = node.type == "bool" and (normalized and 1 or 0) or normalized
                    local nextPacked = public.writeBitsValue(currentPacked, node.offset, node.width, encoded)
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

    function store.readBits(configKey, offset, width)
        return public.readBitsValue(readRaw(configKey), offset, width)
    end

    function store.writeBits(configKey, offset, width, value)
        local current = math.floor(tonumber(readRaw(configKey)) or 0)
        local nextPacked = public.writeBitsValue(current, offset, width, value)
        writeRaw(configKey, nextPacked)
    end

    store.storage = storage
    store.ui = type(definition) == "table" and definition.ui or nil

    if storage then
        store.uiState = shared.CreateUiState(modConfig, backend, storage)
    end

    return store
end
