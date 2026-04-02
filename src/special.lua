local internal = AdamantModpackLib_Internal
local shared = internal.shared
local FieldTypes = shared.FieldTypes
local _coordinators = shared.coordinators
local SpecialFieldKey = shared.SpecialFieldKey
local GetSchemaConfigFields = shared.GetSchemaConfigFields

local function ClonePersistedValue(value)
    if type(value) == "table" then
        return rom.game.DeepCopyTable(value)
    end
    return value
end

local function BuildConfigEntries(configFields, configBackend)
    if not configBackend then
        return nil
    end
    local configEntries = {}
    for _, field in ipairs(configFields) do
        local schemaKey = field._schemaKey or SpecialFieldKey(field.configKey)
        configEntries[schemaKey] = configBackend.getEntry(field.configKey)
    end
    return configEntries
end

local function ReadConfigFieldValue(field, modConfig, configEntries)
    local schemaKey = field._schemaKey or SpecialFieldKey(field.configKey)
    local entry = configEntries and configEntries[schemaKey] or nil
    if entry then
        return entry:get()
    end
    return field._readValue(modConfig)
end

local function WriteConfigFieldValue(field, modConfig, value, configEntries)
    local schemaKey = field._schemaKey or SpecialFieldKey(field.configKey)
    local entry = configEntries and configEntries[schemaKey] or nil
    if entry then
        entry:set(value)
        return
    end
    field._writeValue(modConfig, value)
end

--- Create managed staging state for schema-backed or option-backed UI fields.
--- @param modConfig table Persisted config table backing the state.
--- @param configBackend table|nil Optional Chalk backend wrapper for entry-based read/write access.
--- @param schema table Validated schema/options list.
--- @return table uiState Managed staging object with `view/get/set/update/toggle/reloadFromConfig/flushToConfig`.
function shared.CreateUiState(modConfig, configBackend, schema)
    public.validateSchema(schema, _PLUGIN.guid or "unknown module")

    local staging = {}
    local dirty = false
    local dirtyKeys = {}
    local fieldByKey = {}
    local configFields = GetSchemaConfigFields(schema)
    local configEntries = BuildConfigEntries(configFields, configBackend)
    for _, field in ipairs(configFields) do
        local schemaKey = field._schemaKey or SpecialFieldKey(field.configKey)
        fieldByKey[schemaKey] = field
    end

    local function getField(key)
        return fieldByKey[SpecialFieldKey(key)]
    end

    local function normalizeValue(key, value)
        local field = getField(key)
        if not field then
            return value
        end

        local ft = FieldTypes[field.type]
        if not ft or not ft.toStaging then
            return value
        end
        return ft.toStaging(value, field)
    end

    local function copyConfigToStaging()
        for _, field in ipairs(configFields) do
            local val = ReadConfigFieldValue(field, modConfig, configEntries)
            local ft = FieldTypes[field.type]
            if ft then
                field._writeValue(staging, ft.toStaging(val, field))
            end
        end
    end

    local function copyStagingToConfig()
        for _, field in ipairs(configFields) do
            local schemaKey = field._schemaKey or SpecialFieldKey(field.configKey)
            if dirtyKeys[schemaKey] then
                local val = field._readValue(staging)
                WriteConfigFieldValue(field, modConfig, val, configEntries)
            end
        end
    end

    local function captureDirtyConfigSnapshot()
        local snapshot = {}
        for _, field in ipairs(configFields) do
            local schemaKey = field._schemaKey or SpecialFieldKey(field.configKey)
            if dirtyKeys[schemaKey] then
                table.insert(snapshot, {
                    field = field,
                    value = ClonePersistedValue(ReadConfigFieldValue(field, modConfig, configEntries)),
                })
            end
        end
        return snapshot
    end

    local function restoreConfigSnapshot(snapshot)
        for _, entry in ipairs(snapshot or {}) do
            WriteConfigFieldValue(entry.field, modConfig, ClonePersistedValue(entry.value), configEntries)
        end
    end

    local function markDirty(key)
        local schemaKey = SpecialFieldKey(key)
        if fieldByKey[schemaKey] then
            dirtyKeys[schemaKey] = true
        end
        dirty = true
    end

    local function clearDirty()
        dirty = false
        dirtyKeys = {}
    end

    local function readStagingValue(key)
        local field = getField(key)
        if field then
            return field._readValue(staging), field
        end
        return public.readPath(staging, key), nil
    end

    local function writeStagingValue(key, value)
        local field = getField(key)
        local normalized = normalizeValue(key, value)
        if field then
            field._writeValue(staging, normalized)
        else
            public.writePath(staging, key, normalized)
        end
        markDirty(key)
    end

    copyConfigToStaging()

    local readonlyCache = setmetatable({}, { __mode = "k" })

    local function makeReadonly(node)
        if type(node) ~= "table" then
            return node
        end
        if readonlyCache[node] then
            return readonlyCache[node]
        end

        local proxy = {}
        local mt = {
            __index = function(_, key)
                local value = node[key]
                if type(value) == "table" then
                    return makeReadonly(value)
                end
                return value
            end,
            __newindex = function()
                error("uiState view is read-only; use state.set/update/toggle", 2)
            end,
            __pairs = function()
                return function(_, lastKey)
                    local nextKey, nextVal = next(node, lastKey)
                    if type(nextVal) == "table" then
                        nextVal = makeReadonly(nextVal)
                    end
                    return nextKey, nextVal
                end, proxy, nil
            end,
            __ipairs = function()
                local i = 0
                return function()
                    i = i + 1
                    local value = node[i]
                    if value ~= nil and type(value) == "table" then
                        value = makeReadonly(value)
                    end
                    if value ~= nil then
                        return i, value
                    end
                end, proxy, 0
            end,
        }

        setmetatable(proxy, mt)
        readonlyCache[node] = proxy
        return proxy
    end

    local function snapshot()
        copyConfigToStaging()
        clearDirty()
    end

    local function sync()
        copyStagingToConfig()
        clearDirty()
    end

    return {
        view = makeReadonly(staging),
        get = function(key)
            return readStagingValue(key)
        end,
        set = function(key, value)
            writeStagingValue(key, value)
        end,
        update = function(key, updater)
            local current = readStagingValue(key)
            writeStagingValue(key, updater(current))
        end,
        toggle = function(key)
            local current = readStagingValue(key)
            writeStagingValue(key, not (current == true))
        end,
        reloadFromConfig = snapshot,
        flushToConfig = sync,
        _captureDirtyConfigSnapshot = captureDirtyConfigSnapshot,
        _restoreConfigSnapshot = restoreConfigSnapshot,
        isDirty = function()
            return dirty
        end,
        collectConfigMismatches = function()
            local mismatches = {}
            for _, field in ipairs(configFields) do
                local currentValue = ReadConfigFieldValue(field, modConfig, configEntries)
                local stagedValue = field._readValue(staging)
                local ft = FieldTypes[field.type]
                if ft and ft.toStaging then
                    currentValue = ft.toStaging(currentValue, field)
                end
                if not public.valuesEqual(field, currentValue, stagedValue) then
                    table.insert(mismatches, field._schemaKey or SpecialFieldKey(field.configKey))
                end
            end
            return mismatches
        end,
    }
end

--- Run one managed `uiState` draw pass and persist changes when the pass dirties staging.
--- @param opts table Options table containing:
---   `name`      string|nil  Human-readable label used in warnings.
---   `imgui`     table|nil   ImGui binding to pass to the draw callback.
---   `uiState`   table       Managed uiState object.
---   `theme`     table|nil   Optional theme object forwarded to the draw callback.
---   `draw`      function    Callback `(imgui, uiState, theme)` that renders controls.
---   `commit`    function|nil Optional transactional commit callback `(uiState) -> ok, err`.
---   `onFlushed` function|nil Callback invoked after a successful flush/commit.
--- @return boolean changed True when staged state was successfully flushed or committed.
--- @return string|nil err Error text when a transactional commit failed.
function public.runUiStatePass(opts)
    local draw = opts and opts.draw
    if type(draw) ~= "function" then
        return false
    end

    local uiState = opts.uiState
    if not uiState or type(uiState.isDirty) ~= "function" or type(uiState.flushToConfig) ~= "function" then
        if shared.libWarn then
            shared.libWarn("runUiStatePass: uiState is missing or malformed; pass skipped")
        end
        return false
    end
    draw(opts.imgui or rom.ImGui, uiState, opts.theme)

    if uiState.isDirty() then
        if type(opts.commit) == "function" then
            local ok, err = opts.commit(uiState)
            if ok then
                if type(opts.onFlushed) == "function" then
                    opts.onFlushed()
                end
                return true, nil
            end
            if shared.libWarnAlways then
                shared.libWarnAlways("%s: uiState commit failed: %s",
                    tostring(opts.name or "uiState"),
                    tostring(err))
            end
            return false, err
        end

        uiState.flushToConfig()
        if type(opts.onFlushed) == "function" then
            opts.onFlushed()
        end
        return true
    end

    return false
end

--- Audit staged `uiState` for drift from persisted config, warn on mismatches, then reload.
--- @param name string Human-readable module/special name used in warnings.
--- @param uiState table Managed uiState object.
--- @return table mismatches Array of schema keys that drifted.
function public.auditAndResyncUiState(name, uiState)
    if not uiState or type(uiState.collectConfigMismatches) ~= "function" or type(uiState.reloadFromConfig) ~= "function" then
        return {}
    end

    local mismatches = uiState.collectConfigMismatches()
    if #mismatches > 0 then
        print("[" .. tostring(name) .. "] UI state drift detected; reloading staged values for: " .. table.concat(mismatches, ", "))
    end
    uiState.reloadFromConfig()
    return mismatches
end

--- Flush managed `uiState` transactionally and reapply runtime state when required.
--- On reapply failure, persisted config and staged state are restored to their previous values.
--- @param def table Module definition table.
--- @param store table Module store that owns persisted config and the Enabled bit.
--- @param uiState table Managed uiState object created for the module.
--- @return boolean ok True when the new staged values were committed successfully.
--- @return string|nil err Error text when commit or rollback reapply failed.
function public.commitUiState(def, store, uiState)
    if not uiState or type(uiState.isDirty) ~= "function" or type(uiState.flushToConfig) ~= "function"
        or type(uiState.reloadFromConfig) ~= "function"
        or type(uiState._captureDirtyConfigSnapshot) ~= "function"
        or type(uiState._restoreConfigSnapshot) ~= "function" then
        return false, "uiState is missing transactional commit helpers"
    end

    if not uiState.isDirty() then
        return true, nil
    end

    local snapshot = uiState._captureDirtyConfigSnapshot()
    uiState.flushToConfig()

    local shouldReapply = public.affectsRunData(def)
        and store
        and type(store.read) == "function"
        and store.read("Enabled") == true

    if not shouldReapply then
        return true, nil
    end

    local ok, err = public.reapplyDefinition(def, store)
    if ok then
        return true, nil
    end

    uiState._restoreConfigSnapshot(snapshot)
    uiState.reloadFromConfig()

    local rollbackOk, rollbackErr = public.reapplyDefinition(def, store)
    if not rollbackOk then
        if shared.libWarnAlways then
            shared.libWarnAlways("%s: uiState rollback reapply failed: %s",
                tostring(def.name or def.id or "module"),
                tostring(rollbackErr))
        end
        return false, tostring(err) .. " (rollback reapply failed: " .. tostring(rollbackErr) .. ")"
    end

    return false, err
end

--- Build standalone window + menu-bar callbacks for a special module outside a coordinator.
--- @param def table Special module definition table.
--- @param store table Special module store created by lib.createStore(...).
--- @param uiState table|nil Optional uiState override; defaults to `store.uiState`.
--- @param opts table|nil Optional rendering overrides:
---   `windowTitle`         string|nil
---   `theme`               table|nil
---   `drawQuickContent`    function|nil
---   `drawTab`             function|nil
---   `getDrawQuickContent` function|nil
---   `getDrawTab`          function|nil
--- @return table ui `{ renderWindow, addMenuBar }` callbacks for standalone registration.
function public.standaloneSpecialUI(def, store, uiState, opts)
    opts = opts or {}
    uiState = uiState or (store and store.uiState) or nil

    local function getDrawQuickContent()
        if type(opts.getDrawQuickContent) == "function" then
            return opts.getDrawQuickContent()
        end
        return opts.drawQuickContent
    end

    local function getDrawTab()
        if type(opts.getDrawTab) == "function" then
            return opts.getDrawTab()
        end
        return opts.drawTab
    end

    local function onStateFlushed()
        if public.affectsRunData(def) and store.read("Enabled") == true then
            rom.game.SetupRunData()
        end
    end

    local showWindow = false

    local function renderWindow()
        if def.modpack and _coordinators[def.modpack] then return end
        if not showWindow then return end

        local imgui = rom.ImGui
        local title = (opts.windowTitle or def.name) .. "###" .. tostring(def.id)
        if imgui.Begin(title) then
            local enabled = store.read("Enabled") == true
            local enabledValue, enabledChanged = imgui.Checkbox("Enabled", enabled)
            if enabledChanged then
                local ok, err = public.setDefinitionEnabled(def, store, enabledValue)
                if ok then
                    if public.affectsRunData(def) then
                        rom.game.SetupRunData()
                    end
                else
                    if shared.libWarnAlways then
                        shared.libWarnAlways("%s %s failed: %s",
                            tostring(def.name or def.id or "module"),
                            enabledValue and "enable" or "disable",
                            tostring(err))
                    end
                end
            end

            local debugValue, debugChanged = imgui.Checkbox("Debug Mode", store.read("DebugMode") == true)
            if debugChanged then
                store.write("DebugMode", debugValue)
            end

            if uiState and imgui.Button("Audit + Resync UI State") then
                public.auditAndResyncUiState(def.name or def.id or "module", uiState)
            end

            local drawQuickContent = getDrawQuickContent()
            local drawTab = getDrawTab()

            if drawQuickContent or drawTab then
                imgui.Separator()
                imgui.Spacing()
            end

            if drawQuickContent then
                public.runUiStatePass({
                    name = def.name,
                    imgui = imgui,
                    uiState = uiState,
                    theme = opts.theme,
                    commit = function(state)
                        return public.commitUiState(def, store, state)
                    end,
                    draw = drawQuickContent,
                    onFlushed = onStateFlushed,
                })
            end

            if drawQuickContent and drawTab then
                imgui.Spacing()
                imgui.Separator()
            end

            if drawTab then
                public.runUiStatePass({
                    name = def.name,
                    imgui = imgui,
                    uiState = uiState,
                    theme = opts.theme,
                    commit = function(state)
                        return public.commitUiState(def, store, state)
                    end,
                    draw = drawTab,
                    onFlushed = onStateFlushed,
                })
            end

            imgui.End()
        else
            showWindow = false
        end
    end

    local function addMenuBar()
        if def.modpack and _coordinators[def.modpack] then return end
        if rom.ImGui.BeginMenu(def.name) then
            if rom.ImGui.MenuItem(def.name) then
                showWindow = not showWindow
            end
            rom.ImGui.EndMenu()
        end
    end

    return {
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
    }
end
