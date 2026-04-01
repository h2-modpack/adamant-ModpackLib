local internal = AdamantModpackLib_Internal
local shared = internal.shared
local FieldTypes = shared.FieldTypes
local _coordinators = shared.coordinators
local SpecialFieldKey = shared.SpecialFieldKey
local PrepareSchemaFieldRuntimeMetadata = shared.PrepareSchemaFieldRuntimeMetadata
local IsSchemaConfigField = shared.IsSchemaConfigField
local function GetSchemaConfigFields(schema)
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

--- Create managed staging state for a special module.
--- @param schema table
--- @return table
function shared.CreateSpecialState(store, schema)
    local modConfig = store._config
    public.validateSchema(schema, _PLUGIN.guid or "unknown module")

    local staging = {}
    local dirty = false
    local dirtyKeys = {}
    local fieldByKey = {}
    local configFields = GetSchemaConfigFields(schema)
    local configEntries = BuildConfigEntries(configFields, store._backend)
    for _, field in ipairs(configFields) do
        local schemaKey = field._schemaKey or SpecialFieldKey(field.configKey)
        fieldByKey[schemaKey] = field
    end

    local function normalizeValue(key, value)
        local field = fieldByKey[SpecialFieldKey(key)]
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

    local function markDirty(key)
        local schemaKey = SpecialFieldKey(key)
        if fieldByKey[schemaKey] then
            dirtyKeys[schemaKey] = true
        end
        dirty = true
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
                error("special state view is read-only; use state.set/update/toggle", 2)
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
        dirty = false
        dirtyKeys = {}
    end

    local function sync()
        copyStagingToConfig()
        dirty = false
        dirtyKeys = {}
    end

    return {
        view = makeReadonly(staging),
        get = function(key)
            local field = fieldByKey[SpecialFieldKey(key)]
            if field then
                return field._readValue(staging)
            end
            return public.readPath(staging, key)
        end,
        set = function(key, value)
            local field = fieldByKey[SpecialFieldKey(key)]
            local normalized = normalizeValue(key, value)
            if field then
                field._writeValue(staging, normalized)
            else
                public.writePath(staging, key, normalized)
            end
            markDirty(key)
        end,
        update = function(key, updater)
            local field = fieldByKey[SpecialFieldKey(key)]
            local current = field and field._readValue(staging) or public.readPath(staging, key)
            local normalized = normalizeValue(key, updater(current))
            if field then
                field._writeValue(staging, normalized)
            else
                public.writePath(staging, key, normalized)
            end
            markDirty(key)
        end,
        toggle = function(key)
            local field = fieldByKey[SpecialFieldKey(key)]
            local current = field and field._readValue(staging) or public.readPath(staging, key)
            local normalized = normalizeValue(key, not (current == true))
            if field then
                field._writeValue(staging, normalized)
            else
                public.writePath(staging, key, normalized)
            end
            markDirty(key)
        end,
        reloadFromConfig = snapshot,
        flushToConfig = sync,
        isDirty = function()
            return dirty
        end,
    }
end

--- Run one special-module UI draw pass and flush managed state if dirty.
--- @param opts table
--- @return boolean
function public.runSpecialUiPass(opts)
    local draw = opts and opts.draw
    if type(draw) ~= "function" then
        return false
    end

    local specialState = opts.specialState
    if not specialState or type(specialState.isDirty) ~= "function" or type(specialState.flushToConfig) ~= "function" then
        if shared.libWarn then
            shared.libWarn("runSpecialUiPass: specialState is missing or malformed; pass skipped")
        end
        return false
    end
    draw(opts.imgui or rom.ImGui, specialState, opts.theme)

    if specialState.isDirty() then
        specialState.flushToConfig()
        if type(opts.onFlushed) == "function" then
            opts.onFlushed()
        end
        return true
    end

    return false
end

--- Build standalone window + menu-bar callbacks for a special module.
--- @param def table
--- @param store table
--- @param specialState table
--- @param apply function
--- @param revert function
--- @param opts table|nil
--- @return table
function public.standaloneSpecialUI(def, store, specialState, apply, revert, opts)
    opts = opts or {}

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
        if def.dataMutation and store.read("Enabled") == true then
            revert()
            apply()
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
                store.write("Enabled", enabledValue)
                if enabledValue then
                    apply()
                else
                    revert()
                end
                if def.dataMutation then
                    rom.game.SetupRunData()
                end
            end

            local debugValue, debugChanged = imgui.Checkbox("Debug Mode", store.read("DebugMode") == true)
            if debugChanged then
                store.write("DebugMode", debugValue)
            end

            local drawQuickContent = getDrawQuickContent()
            local drawTab = getDrawTab()

            if drawQuickContent or drawTab then
                imgui.Separator()
                imgui.Spacing()
            end

            if drawQuickContent then
                public.runSpecialUiPass({
                    name = def.name,
                    imgui = imgui,
                    specialState = specialState,
                    theme = opts.theme,
                    draw = drawQuickContent,
                    onFlushed = onStateFlushed,
                })
            end

            if drawQuickContent and drawTab then
                imgui.Spacing()
                imgui.Separator()
            end

            if drawTab then
                public.runSpecialUiPass({
                    name = def.name,
                    imgui = imgui,
                    specialState = specialState,
                    theme = opts.theme,
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
