local internal = AdamantModpackLib_Internal
local shared = internal.shared
local libConfig = shared.libConfig
local _coordinators = shared.coordinators
local chalk = shared.chalk
local _mutationRuntime = shared.mutationRuntime or setmetatable({}, { __mode = "k" })
shared.mutationRuntime = _mutationRuntime
local SpecialFieldKey
local PrepareSchemaFieldRuntimeMetadata
local IsSchemaConfigField
local GetSchemaConfigFields
local ChoiceDisplay

--- Register or clear the coordinator config used for pack-level enable gating.
--- Called by Framework.init on behalf of the coordinator.
--- @param packId string Stable modpack identifier shared by coordinator and modules.
--- @param config table|nil Coordinator config table, or nil to deregister during tests/reload.
function public.registerCoordinator(packId, config)
    _coordinators[packId] = config
end

--- Return whether a coordinator config is currently registered for the given pack.
--- @param packId string Stable modpack identifier.
--- @return boolean isRegistered True when a coordinator config is available.
function public.isCoordinated(packId)
    return _coordinators[packId] ~= nil
end

--- Return whether a store-backed module should currently be active.
--- Considers both the module's own Enabled bit and an optional coordinator ModEnabled gate.
--- @param store table Store created by lib.createStore(...).
--- @param packId string|nil Optional modpack identifier for coordinator gating.
--- @return boolean isEnabled True when runtime behavior should be active.
function public.isEnabled(store, packId)
    local coord = packId and _coordinators[packId]
    if coord and not coord.ModEnabled then return false end
    return store and type(store.read) == "function" and store.read("Enabled") == true or false
end

--- Lib-internal diagnostic — gated on lib's own DebugMode.
local function FormatWarning(prefix, fmt, ...)
    return prefix .. (select('#', ...) > 0 and string.format(fmt, ...) or fmt)
end

--- Lib-internal diagnostic — gated on lib's own DebugMode.
local function libWarn(fmt, ...)
    if not libConfig.DebugMode then return end
    print(FormatWarning("[lib] ", fmt, ...))
end
shared.libWarn = libWarn

--- Lib-internal contract warning — always printed.
local function libWarnAlways(fmt, ...)
    print(FormatWarning("[lib] ", fmt, ...))
end
shared.libWarnAlways = libWarnAlways

--- Print a framework diagnostic warning when the caller's debug flag is enabled.
--- @param packId string Pack identifier used as the warning prefix.
--- @param enabled boolean Debug gate; false suppresses output.
--- @param fmt string Message text or string.format pattern.
--- @vararg any Format arguments used with fmt.
function public.warn(packId, enabled, fmt, ...)
    if not enabled then return end
    print(FormatWarning("[" .. packId .. "] ", fmt, ...))
end

--- Print a framework contract or compatibility warning. Always printed.
--- @param packId string Pack identifier used as the warning prefix.
--- @param fmt string Message text or string.format pattern.
--- @vararg any Format arguments used with fmt.
function public.contractWarn(packId, fmt, ...)
    print(FormatWarning("[" .. packId .. "] ", fmt, ...))
end

--- Print a module-level diagnostic trace when that module's DebugMode is enabled.
--- @param name string Module display name used as the warning prefix.
--- @param enabled boolean Debug gate; false suppresses output.
--- @param fmt string Message text or string.format pattern.
--- @vararg any Format arguments used with fmt.
function public.log(name, enabled, fmt, ...)
    if not enabled then return end
    print("[" .. name .. "] " .. (select('#', ...) > 0 and string.format(fmt, ...) or fmt))
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

--- Create an isolated backup/restore pair for manual mutation lifecycles.
--- The backup function snapshots keys on first touch; the restore function reverts all captured values.
--- @return function backup Function `(tbl, ...)` that snapshots one or more keys on a table.
--- @return function restore Function `()` that restores every captured key to its original value.
function public.createBackupSystem()
    local NIL = {}
    local savedValues = {}

    local function backup(tbl, ...)
        savedValues[tbl] = savedValues[tbl] or {}
        local saved = savedValues[tbl]
        for i = 1, select('#', ...) do
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

--- Create a reversible declarative mutation plan for patch-style data edits.
--- Returned plans support `set`, `setMany`, `transform`, `append`, `appendUnique`, `apply`, and `revert`.
--- @return table plan Mutation plan object.
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
                    if tbl[key] == list then
                        backup(tbl, key)
                    end
                    list[#list + 1] = CloneMutationValue(op.value)
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

--- Infer a module's mutation authoring shape from its exported lifecycle surface.
--- @param def table|nil Module definition table.
--- @return string|nil shape `"patch"`, `"manual"`, `"hybrid"`, or nil when no lifecycle is exposed.
--- @return table info Lifecycle capability flags `{ hasPatch, hasApply, hasRevert, hasManual }`.
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

--- Return whether this module's config/lifecycle changes require run-data rebuild behavior.
--- @param def table|nil Module definition table.
--- @return boolean affectsRunData True when run-data rebuild/reapply should occur after successful changes.
function public.affectsRunData(def)
    if not def then
        return false
    end
    return def.affectsRunData == true
end

--- Compare two field values using field-type equality when provided, otherwise deep structural equality.
--- @param field table|nil Field definition used to resolve an optional field-type-specific equality function.
--- @param a any First value.
--- @param b any Second value.
--- @return boolean equal True when the values are semantically equal.
function public.valuesEqual(field, a, b)
    local fieldTypes = shared.FieldTypes
    local fieldType = field and fieldTypes and field.type and fieldTypes[field.type] or nil
    if fieldType and type(fieldType.equals) == "function" then
        return fieldType.equals(field, a, b)
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

--- Activate a module definition using inferred patch/manual/hybrid mutation behavior.
--- @param def table Module definition table.
--- @param store table|nil Module store used for patch-plan ownership and config reads.
--- @return boolean ok True when activation succeeded.
--- @return string|nil err Error text when activation failed.
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

--- Deactivate a module definition using inferred patch/manual/hybrid mutation behavior.
--- @param def table Module definition table.
--- @param store table|nil Module store used for active patch-plan lookup.
--- @return boolean ok True when deactivation succeeded.
--- @return string|nil err Error text when deactivation failed.
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

--- Persist a definition's Enabled state only after the corresponding lifecycle work succeeds.
--- Already-enabled `true` requests trigger a reapply; already-disabled `false` requests are no-ops.
--- @param def table Module definition table.
--- @param store table Module store that owns the persisted Enabled flag.
--- @param enabled boolean Desired persisted/runtime state.
--- @return boolean ok True when the requested state was committed successfully.
--- @return string|nil err Error text when lifecycle work failed.
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

--- Reapply a definition by reverting the current runtime state and applying it again.
--- @param def table Module definition table.
--- @param store table Module store used for patch-plan lookup and config reads.
--- @return boolean ok True when reapply succeeded.
--- @return string|nil err Error text when revert or apply failed.
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

local function BuildManagedFields(definition)
    if type(definition) ~= "table" then
        return nil
    end

    if definition.stateSchema ~= nil
        or definition.options ~= nil
        or definition.special ~= nil
        or definition.id ~= nil
    then
        local label = tostring(definition.name or definition.id or _PLUGIN.guid or "module")

        if type(definition.stateSchema) == "table" then
            return definition.stateSchema
        end

        if definition.special then
            libWarnAlways("%s: special modules must declare definition.stateSchema; no uiState created", label)
            return nil
        end

        if type(definition.options) == "table" then
            local managedFields = {}
            local hasManagedField = false
            for _, field in ipairs(definition.options) do
                if field.type == "separator" then
                    table.insert(managedFields, field)
                elseif type(field.configKey) == "table" then
                    libWarnAlways("%s: regular definition.options configKey must be a flat string; nested option skipped",
                        label)
                else
                    table.insert(managedFields, field)
                    hasManagedField = true
                end
            end
            if hasManagedField then
                return managedFields
            end
            return nil
        end
        return nil
    end

    if #definition > 0 then
        error("createStore expects a module definition table; raw schema/options arrays are not supported", 2)
    end
    return nil
end

--- Build a standalone menu-bar callback for a regular module outside a coordinator.
--- @param def table Module definition table.
--- @param store table Module store created by lib.createStore(...).
--- @return function renderMenu Callback suitable for `rom.gui.add_to_menu_bar(...)`.
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

    local function IsOptionVisible(opt)
        if not opt.visibleIf then
            return true
        end
        local uiState = store.uiState
        if not uiState or not uiState.view then
            return false
        end
        return uiState.view[opt.visibleIf] == true
    end

    local function DrawOption(imgui, opt, index)
        if not IsOptionVisible(opt) then
            return
        end

        local pushId = opt._pushId or opt.configKey or (opt.type .. "_" .. tostring(index))
        imgui.PushID(pushId)
        if opt.indent then
            imgui.Indent()
        end

        local currentValue = nil
        if opt.configKey ~= nil then
            currentValue = store.uiState and store.uiState.get(opt.configKey) or nil
        end
        local newVal, newChg = public.drawField(imgui, opt, currentValue)
        if newChg and opt.configKey then
            store.uiState.set(opt.configKey, newVal)
        end

        if opt.indent then
            imgui.Unindent()
        end
        imgui.PopID()
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

            if enabled and def.options then
                imgui.Separator()
                public.runUiStatePass({
                    name = def.name,
                    imgui = imgui,
                    uiState = store.uiState,
                    commit = function(state)
                        return public.commitUiState(def, store, state)
                    end,
                    draw = function()
                        for index, opt in ipairs(def.options) do
                            DrawOption(imgui, opt, index)
                        end
                    end,
                    onFlushed = onUiStateFlushed,
                })
            end

            imgui.EndMenu()
        end
    end
end

--- Read a value from a table using a flat key or nested path.
--- @param tbl table Root table to read from.
--- @param key string|table Flat config key or `{...}` path.
--- @return any value Current value, or nil when the path is missing.
--- @return table|nil parent Parent table containing the resolved key, when found.
--- @return string|nil leafKey Final key segment used for the lookup, when found.
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

--- Write a value to a table using a flat key or nested path.
--- Missing intermediate tables are created automatically for nested paths.
--- @param tbl table Root table to write into.
--- @param key string|table Flat config key or `{...}` path.
--- @param value any Value to persist.
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

--- Create the module-owned store facade around persisted config.
--- Pass the module definition table to enable managed `uiState` for `options` or `stateSchema`.
--- @param modConfig table Persisted config table, usually from Chalk.
--- @param definition table|nil Module definition table, or nil for a plain store without `uiState`.
--- @return table store Store exposing `read`, `write`, and optional `uiState`.
function public.createStore(modConfig, definition)
    local backend = GetConfigBackend(modConfig)
    local store = {}

    function store.read(key)
        if backend then
            local value = backend.readValue(key)
            if value ~= nil then
                return value
            end
        end
        return public.readPath(modConfig, key)
    end

    function store.write(key, value)
        if backend and backend.writeValue(key, value) then
            return
        end
        public.writePath(modConfig, key, value)
    end

    local managedFields = BuildManagedFields(definition)
    if managedFields then
        store.uiState = shared.CreateUiState(modConfig, backend, managedFields)
    end

    return store
end

PrepareSchemaFieldRuntimeMetadata = function(field)
    if not field or field.configKey == nil then
        return
    end
    field._schemaKey = field._schemaKey or SpecialFieldKey(field.configKey)
    if not field._readValue or not field._writeValue then
        local configKey = field.configKey
        if type(configKey) ~= "table" then
            local key = configKey
            field._readValue = function(tbl)
                return tbl[key]
            end
            field._writeValue = function(tbl, value)
                tbl[key] = value
            end
            return
        end

        local len = #configKey
        if len == 0 then
            field._readValue = function()
                return nil
            end
            field._writeValue = function()
            end
            return
        end

        if len == 1 then
            local key = configKey[1]
            field._readValue = function(tbl)
                return tbl[key]
            end
            field._writeValue = function(tbl, value)
                tbl[key] = value
            end
            return
        end

        if len == 2 then
            local key1, key2 = configKey[1], configKey[2]
            field._readValue = function(tbl)
                local child = tbl[key1]
                return child and child[key2] or nil
            end
            field._writeValue = function(tbl, value)
                local child = tbl[key1]
                if not child then
                    child = {}
                    tbl[key1] = child
                end
                child[key2] = value
            end
            return
        end

        if len == 3 then
            local key1, key2, key3 = configKey[1], configKey[2], configKey[3]
            field._readValue = function(tbl)
                local child1 = tbl[key1]
                if not child1 then return nil end
                local child2 = child1[key2]
                return child2 and child2[key3] or nil
            end
            field._writeValue = function(tbl, value)
                local child1 = tbl[key1]
                if not child1 then
                    child1 = {}
                    tbl[key1] = child1
                end
                local child2 = child1[key2]
                if not child2 then
                    child2 = {}
                    child1[key2] = child2
                end
                child2[key3] = value
            end
            return
        end

        field._readValue = function(tbl)
            return public.readPath(tbl, configKey)
        end
        field._writeValue = function(tbl, value)
            public.writePath(tbl, configKey, value)
        end
    end
end
shared.PrepareSchemaFieldRuntimeMetadata = PrepareSchemaFieldRuntimeMetadata

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

function GetConfigBackend(config)
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
        local pathKey = SpecialFieldKey(configKey)
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

SpecialFieldKey = function(configKey)
    if type(configKey) == "table" then
        return table.concat(configKey, ".")
    end
    return tostring(configKey)
end
shared.SpecialFieldKey = SpecialFieldKey

IsSchemaConfigField = function(field)
    return field and field.type ~= "separator" and field.configKey ~= nil
end
shared.IsSchemaConfigField = IsSchemaConfigField

GetSchemaConfigFields = function(schema)
    if type(schema) ~= "table" then
        return {}
    end

    local configFields = rawget(schema, "_configFields")
    if configFields then
        return configFields
    end

    configFields = {}
    for _, field in ipairs(schema) do
        if IsSchemaConfigField(field) then
            PrepareSchemaFieldRuntimeMetadata(field)
            table.insert(configFields, field)
        end
    end
    schema._configFields = configFields
    return configFields
end
shared.GetSchemaConfigFields = GetSchemaConfigFields
--- Return the config-backed fields in a validated schema, excluding separators.
--- Runtime metadata is prepared lazily and cached on the schema table.
--- @param schema table|nil Validated schema or options list.
--- @return table configFields Array of config-backed field definitions.
public.getSchemaConfigFields = GetSchemaConfigFields

ChoiceDisplay = function(field, value)
    if field.displayValues and field.displayValues[value] ~= nil then
        return tostring(field.displayValues[value])
    end
    return tostring(value)
end
shared.ChoiceDisplay = ChoiceDisplay
