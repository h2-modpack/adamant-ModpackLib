-- =============================================================================
-- ADAMANT-LIB: Shared utilities for adamant standalone mods
-- =============================================================================
-- Access via: local lib = rom.mods['adamant-ModpackLib']
--
-- Provides:
--   backup, restore = lib.createBackupSystem()
--   local cb = lib.standaloneUI(def, config, apply, revert)  -- returns callback
--   rom.gui.add_to_menu_bar(cb)  -- caller registers in own plugin context
--   specialState = lib.createSpecialState(config, schema)
--   lib.isEnabled(modConfig, packId) — true if module AND coordinator's ModEnabled are both on
--   lib.isCoordinated(packId) — true if a coordinator has registered for this packId
--   lib.registerCoordinator(packId, config) — called by Framework.init
--   lib.warn(packId, enabled, msg) — framework diagnostic, gated on caller's enabled flag
--   lib.log(name, enabled, msg) — module trace, gated on caller's config.DebugMode
--   lib.FieldTypes — central registry of field types (checkbox, dropdown, radio)
--   lib.drawField(imgui, field, value, width) — render a field widget

local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN

local chalk = mods['SGG_Modding-Chalk']
local libConfig = chalk.auto('config.lua')
public.config = libConfig

-- Forward declaration — populated at bottom of file
local FieldTypes = {}

-- Registry of active coordinators: packId -> config
-- Written by lib.registerCoordinator (called from Framework.init).
-- Read by isEnabled, isCoordinated, standaloneUI, and the lib debug menu.
local _coordinators = {}

--- Register a coordinator's config under its packId.
--- Called by Framework.init on behalf of the coordinator.
--- Pass nil to deregister (used in tests and hot-reload).
--- @param packId string       The pack identifier
--- @param config table|nil    The coordinator's Chalk config (needs .ModEnabled), or nil to clear
function public.registerCoordinator(packId, config)
    _coordinators[packId] = config
end

--- Return true if a coordinator has registered for this packId.
--- Modules use this to decide whether to self-apply SetupRunData.
--- @param packId string
--- @return boolean
function public.isCoordinated(packId)
    return _coordinators[packId] ~= nil
end

--- Check if a module should be active.
--- Returns true only if the module's own Enabled flag is true AND
--- the coordinator's ModEnabled is true (when a coordinator is registered).
--- When no coordinator is registered, only the module's own flag is checked.
--- @param modConfig table  The module's chalk config (needs .Enabled)
--- @param packId string    The pack identifier from definition.modpack
--- @return boolean
function public.isEnabled(modConfig, packId)
    local coord = packId and _coordinators[packId]
    if coord and not coord.ModEnabled then return false end
    return modConfig.Enabled == true
end

--- Lib-internal diagnostic — gated on lib's own DebugMode (libConfig.DebugMode).
--- Used by validateSchema, FieldTypes, and drawField. Not part of the public API.
local function libWarn(fmt, ...)
    if not libConfig.DebugMode then return end
    print("[lib] " .. (select('#', ...) > 0 and string.format(fmt, ...) or fmt))
end

--- Print a framework diagnostic warning, gated on the caller's enabled flag.
--- Accepts printf-style args: warn(packId, enabled, "foo %s", bar).
--- String building is deferred past the gate — no allocation when disabled.
--- @param packId  string
--- @param enabled boolean
--- @param fmt     string
--- @param ...     any
function public.warn(packId, enabled, fmt, ...)
    if not enabled then return end
    print("[" .. packId .. "] " .. (select('#', ...) > 0 and string.format(fmt, ...) or fmt))
end

--- Print a module-level diagnostic trace when the module's own DebugMode is enabled.
--- Accepts printf-style args: log(name, enabled, "foo %s", bar).
--- String building is deferred past the gate — no allocation when disabled.
--- @param name    string
--- @param enabled boolean
--- @param fmt     string
--- @param ...     any
function public.log(name, enabled, fmt, ...)
    if not enabled then return end
    print("[" .. name .. "] " .. (select('#', ...) > 0 and string.format(fmt, ...) or fmt))
end

--- Create an isolated backup/restore pair.
--- Each mod gets its own state — no collision between mods.
--- backup() accepts variadic keys: backup(tbl, "k1", "k2", ...)
--- @return function backup
--- @return function restore
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

--- Build a menu-bar callback for a boolean mod.
--- Returns a function — the caller must register it via rom.gui.add_to_menu_bar().
--- Skips rendering when modpack coordinator is installed.
--- @param def table         public.definition (needs .name, .tooltip, .dataMutation)
--- @param modConfig table   the mod's chalk config (needs .Enabled)
--- @param apply function    called to apply game mutations
--- @param revert function   called to revert game mutations
--- @return function callback
function public.standaloneUI(def, modConfig, apply, revert)
    local function onOptionChanged()
        if def.dataMutation then
            revert()
            apply()
            rom.game.SetupRunData()
        end
    end

    local function DrawOption(imgui, opt, index)
        if not public.isFieldVisible(opt, modConfig) then
            return
        end

        local pushId = opt._pushId or opt.configKey or (opt.type .. "_" .. tostring(index))
        imgui.PushID(pushId)
        if opt.indent then
            imgui.Indent()
        end

        local currentValue = opt.configKey and modConfig[opt.configKey] or nil
        local newVal, newChg = public.drawField(imgui, opt, currentValue)
        if newChg and opt.configKey then
            modConfig[opt.configKey] = newVal
            onOptionChanged()
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
            local val, chg = imgui.Checkbox(def.name, modConfig.Enabled)
            if chg then
                modConfig.Enabled = val
                if val then apply() else revert() end
                if def.dataMutation then rom.game.SetupRunData() end
            end
            if imgui.IsItemHovered() and (def.tooltip or "") ~= "" then
                imgui.SetTooltip(def.tooltip)
            end

            -- Debug mode toggle
            local dbgVal, dbgChg = imgui.Checkbox("Debug Mode", modConfig.DebugMode == true)
            if dbgChg then
                modConfig.DebugMode = dbgVal
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip("Print diagnostic warnings to the console for this module.")
            end

            -- Inline options (when module is enabled)
            if modConfig.Enabled and def.options then
                imgui.Separator()
                for index, opt in ipairs(def.options) do
                    DrawOption(imgui, opt, index)
                end
            end

            imgui.EndMenu()
        end
    end
end

-- =============================================================================
-- HELPERS
-- =============================================================================

--- Read a value from a table using a configKey (string or table path).
--- @param tbl table    The root table to read from
--- @param key string|table  A string key or table path e.g. {"FirstHammers", "BaseStaffAspect"}
--- @return any value, table|nil parentTbl, string|nil leafKey
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

--- Write a value to a table using a configKey (string or table path).
--- Creates intermediate tables for nested paths.
--- @param tbl table    The root table to write to
--- @param key string|table  A string key or table path
--- @param value any    The value to write
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

-- Stable string key for a configKey that may be a string or table path.
-- {"Parent", "Child"} -> "Parent.Child",  "SimpleKey" -> "SimpleKey"
local function SpecialFieldKey(configKey)
    if type(configKey) == "table" then
        return table.concat(configKey, ".")
    end
    return tostring(configKey)
end

-- =============================================================================
-- FIELD TYPE DISPATCHERS
-- =============================================================================

--- Render a schema field widget. Returns (newValue, changed).
--- @param imgui table       ImGui handle
--- @param field table       Field descriptor
--- @param value any         Current value
--- @param width number|nil  Optional pixel width for input fields
--- @return any newValue, boolean changed
function public.drawField(imgui, field, value, width)
    local ft = FieldTypes[field.type]
    if ft then
        if not field._imguiId then
            field._imguiId = "##" .. tostring(field.configKey)
        end
        return ft.draw(imgui, field, value, width)
    end
    libWarn("drawField: unknown type '%s'", field.type)
    return value, false
end

--- Return whether a field should be rendered given the current flat option values.
--- When field.visibleIf is absent, fields are always visible.
--- @param field table
--- @param values table
--- @return boolean
function public.isFieldVisible(field, values)
    if not field.visibleIf then
        return true
    end
    return values and values[field.visibleIf] == true or false
end

--- Validate a schema at declaration time. Warns via lib.warn (debug-guarded).
--- @param schema table   Ordered list of field descriptors
--- @param label string   Name shown in warnings (e.g. module name)
function public.validateSchema(schema, label)
    if type(schema) ~= "table" then
        libWarn("%s: schema is not a table", label)
        return
    end
    for i, field in ipairs(schema) do
        local prefix = label .. " field #" .. i
        if field.type ~= "separator" and not field.configKey then
            libWarn("%s: missing configKey", prefix)
        end
        if field.configKey then
            field._schemaKey = SpecialFieldKey(field.configKey)
        end
        if not field.type then
            libWarn("%s: missing type", prefix)
        else
            local ft = FieldTypes[field.type]
            if not ft then
                libWarn("%s: unknown type '%s'", prefix, field.type)
            elseif ft.validate then
                field._imguiId = "##" .. tostring(field.configKey)
                ft.validate(field, prefix)
            end
            if field.visibleIf ~= nil and type(field.visibleIf) ~= "string" then
                libWarn("%s: visibleIf must be a flat string configKey", prefix)
            end
            if field.indent ~= nil and type(field.indent) ~= "boolean" then
                libWarn("%s: indent must be boolean", prefix)
            end
        end
    end
end

-- =============================================================================
-- SPECIAL MODULE STATE
-- =============================================================================
-- Staging system for special modules. Provides a plain Lua table mirroring
-- the Chalk config for fast UI reads/writes.
--
-- Schema is an ordered list of field descriptors. Supported types:
--
--   "checkbox" — single boolean toggle
--     { type="checkbox", configKey="X", default=false }
--
--   "dropdown" — pick one from a list (combo box)
--     { type="dropdown", configKey="X", values={...}, default="" }
--
--   "radio"    — pick one from a list (radio buttons)
--     { type="radio", configKey="X", values={...}, default="" }
--
-- configKey can be a string ("Mode") or a table path ({"FirstHammers", "BaseStaffAspect"})
-- for nested config access.
--
-- Hashing is handled by Core via definition.stateSchema — modules don't encode/decode.
--
-- Returns: specialState
--
--- @param modConfig table  The module's chalk config
--- @param schema table     Ordered list of field descriptors
--- @return table specialState  Managed special-state object
function public.createSpecialState(modConfig, schema)
    public.validateSchema(schema, _PLUGIN.guid or "unknown module")

    local staging = {}
    local dirty = false

    -- -----------------------------------------------------------------
    -- Copy helpers (using shared path accessors)
    -- -----------------------------------------------------------------
    local readPath  = public.readPath
    local writePath = public.writePath

    local function copyConfigToStaging()
        for _, field in ipairs(schema) do
            local val = readPath(modConfig, field.configKey)
            local ft = FieldTypes[field.type]
            if ft then
                writePath(staging, field.configKey, ft.toStaging(val, field))
            end
        end
    end

    local function copyStagingToConfig()
        for _, field in ipairs(schema) do
            local val = readPath(staging, field.configKey)
            writePath(modConfig, field.configKey, val)
        end
    end

    -- -----------------------------------------------------------------
    -- Initialize staging from current config
    -- -----------------------------------------------------------------
    copyConfigToStaging()

    -- -----------------------------------------------------------------
    -- Read-only view (recursive proxy over staging)
    -- -----------------------------------------------------------------

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

    -- -----------------------------------------------------------------
    -- Public functions
    -- -----------------------------------------------------------------

    local function snapshot()
        copyConfigToStaging()
        dirty = false
    end

    local function sync()
        copyStagingToConfig()
        dirty = false
    end

    local specialState = {
        view = makeReadonly(staging),
        get = function(key)
            local value = readPath(staging, key)
            return value
        end,
        set = function(key, value)
            writePath(staging, key, value)
            dirty = true
        end,
        update = function(key, updater)
            local current = readPath(staging, key)
            writePath(staging, key, updater(current))
            dirty = true
        end,
        toggle = function(key)
            local current = readPath(staging, key)
            writePath(staging, key, not (current == true))
            dirty = true
        end,
        reloadFromConfig = snapshot,
        flushToConfig = sync,
        isDirty = function()
            return dirty
        end,
    }

    return specialState
end

-- =============================================================================
-- SPECIAL MODULE DEBUG HELPERS
-- =============================================================================

--- Capture the current config values for a special module's schema-backed fields.
--- Useful for detecting direct config writes during DrawTab/DrawQuickContent.
--- @param modConfig table
--- @param schema table
--- @return table snapshot
function public.captureSpecialConfigSnapshot(modConfig, schema)
    local snapshot = {}
    for _, field in ipairs(schema or {}) do
        snapshot[field._schemaKey or SpecialFieldKey(field.configKey)] = public.readPath(modConfig, field.configKey)
    end
    return snapshot
end

--- Debug helper: warn if schema-backed config changed during draw without going through specialState.
--- @param name string
--- @param enabled boolean
--- @param specialState table
--- @param modConfig table
--- @param schema table
--- @param before table
function public.warnIfSpecialConfigBypassedState(name, enabled, specialState, modConfig, schema, before)
    if not enabled then return end
    if specialState.isDirty() then return end
    for _, field in ipairs(schema or {}) do
        local key = field._schemaKey or SpecialFieldKey(field.configKey)
        local current = public.readPath(modConfig, field.configKey)
        if current ~= before[key] then
            public.log(name, true,
                "special UI modified config directly; use public.specialState for schema-backed state")
            return
        end
    end
end

local function NormalizeInteger(field, value)
    local num = tonumber(value)
    if num == nil then
        num = tonumber(field.default) or 0
    end
    num = math.floor(num)
    if field.min ~= nil and num < field.min then
        num = field.min
    end
    if field.max ~= nil and num > field.max then
        num = field.max
    end
    return num
end

-- =============================================================================
-- FIELD TYPE REGISTRY
-- =============================================================================
-- Central definition of all schema field types. Each type declares its own:
--   validate(field, prefix)            — declaration-time validation
--   toHash(field, value)               — serialize value to canonical hash string
--   fromHash(field, str)               — deserialize value from canonical hash string
--   toStaging(val)                     — transform value for staging table
--   draw(imgui, field, value, width)   — render widget, returns (newValue, changed)
--
-- To add a new type: add one entry here. All consumers dispatch automatically.

FieldTypes.checkbox = {
    validate = function(field, prefix)
        if field.default ~= nil and type(field.default) ~= "boolean" then
            libWarn("%s: checkbox default must be boolean, got %s", prefix, type(field.default))
        end
    end,
    toHash    = function(_, value) return value and "1" or "0" end,
    fromHash  = function(_, str)   return str == "1" end,
    toStaging = function(val) return val == true end,
    draw = function(imgui, field, value)
        if value == nil then value = field.default end
        local newVal, changed = imgui.Checkbox(field.label or field.configKey, value or false)
        if imgui.IsItemHovered() and (field.tooltip or "") ~= "" then
            imgui.SetTooltip(field.tooltip)
        end
        return newVal, changed
    end,
}

FieldTypes.dropdown = {
    validate = function(field, prefix)
        if not field.values then
            libWarn("%s: dropdown missing values list", prefix)
        elseif type(field.values) ~= "table" or #field.values == 0 then
            libWarn("%s: dropdown values must be a non-empty list", prefix)
        else
            for _, v in ipairs(field.values) do
                if type(v) == "string" and string.find(v, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, v)
                end
            end
        end
    end,
    toHash   = function(_, value) return tostring(value) end,
    fromHash = function(field, str)
        for _, v in ipairs(field.values or {}) do
            if v == str then return str end
        end
        return field.default
    end,
    toStaging = function(val) return val end,
    draw = function(imgui, field, value, width)
        local current = value or field.default or ""
        local currentIdx = 1
        for i, v in ipairs(field.values) do
            if v == current then currentIdx = i; break end
        end
        local preview = field.values[currentIdx] or ""
        imgui.Text(field.label or field.configKey)
        if imgui.IsItemHovered() and (field.tooltip or "") ~= "" then
            imgui.SetTooltip(field.tooltip)
        end
        imgui.SameLine()
        if width then imgui.PushItemWidth(width) end
        local changed = false
        local newVal = current
        if imgui.BeginCombo(field._imguiId, preview) then
            for i, v in ipairs(field.values) do
                if imgui.Selectable(v, i == currentIdx) then
                    if i ~= currentIdx then
                        newVal = v
                        changed = true
                    end
                end
            end
            imgui.EndCombo()
        end
        if width then imgui.PopItemWidth() end
        return newVal, changed
    end,
}

FieldTypes.radio = {
    validate = function(field, prefix)
        if not field.values then
            libWarn("%s: radio missing values list", prefix)
        elseif type(field.values) ~= "table" or #field.values == 0 then
            libWarn("%s: radio values must be a non-empty list", prefix)
        else
            for _, v in ipairs(field.values) do
                if type(v) == "string" and string.find(v, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, v)
                end
            end
        end
    end,
    toHash   = function(_, value) return tostring(value) end,
    fromHash = function(field, str)
        for _, v in ipairs(field.values or {}) do
            if v == str then return str end
        end
        return field.default
    end,
    toStaging = function(val) return val end,
    draw = function(imgui, field, value)
        local current = value or field.default or ""
        imgui.Text(field.label or field.configKey)
        if imgui.IsItemHovered() and (field.tooltip or "") ~= "" then
            imgui.SetTooltip(field.tooltip)
        end
        local newVal = current
        local changed = false
        for _, v in ipairs(field.values) do
            if imgui.RadioButton(v, current == v) then
                if v ~= current then
                    newVal = v
                    changed = true
                end
            end
            imgui.SameLine()
        end
        imgui.NewLine()
        return newVal, changed
    end,
}

FieldTypes.int32 = {
    validate = function(field, prefix)
        if field.default ~= nil and type(field.default) ~= "number" then
            libWarn("%s: int32 default must be number, got %s", prefix, type(field.default))
        end
    end,
    toHash = function(field, value)
        return tostring(NormalizeInteger(field, value))
    end,
    fromHash = function(field, str)
        return NormalizeInteger(field, tonumber(str))
    end,
    toStaging = function(val, field)
        return NormalizeInteger(field or {}, val)
    end,
    draw = function(_, _, value)
        return value, false
    end,
}

FieldTypes.stepper = {
    validate = function(field, prefix)
        if type(field.default) ~= "number" then
            libWarn("%s: stepper default must be number, got %s", prefix, type(field.default))
        end
        if type(field.min) ~= "number" then
            libWarn("%s: stepper min must be number, got %s", prefix, type(field.min))
        end
        if type(field.max) ~= "number" then
            libWarn("%s: stepper max must be number, got %s", prefix, type(field.max))
        end
        if type(field.min) == "number" and type(field.max) == "number" and field.min > field.max then
            libWarn("%s: stepper min cannot exceed max", prefix)
        end
        if field.step ~= nil and (type(field.step) ~= "number" or field.step <= 0) then
            libWarn("%s: stepper step must be a positive number", prefix)
        end
        field._step = math.floor(tonumber(field.step) or 1)
    end,
    toHash = function(field, value)
        return tostring(NormalizeInteger(field, value))
    end,
    fromHash = function(field, str)
        return NormalizeInteger(field, tonumber(str))
    end,
    toStaging = function(val, field)
        return NormalizeInteger(field or {}, val)
    end,
    draw = function(imgui, field, value)
        local current = NormalizeInteger(field, value)
        local step = field._step or math.floor(tonumber(field.step) or 1)
        local changed = false
        local newVal = current

        imgui.Text(field.label or field.configKey)
        if imgui.IsItemHovered() and (field.tooltip or "") ~= "" then
            imgui.SetTooltip(field.tooltip)
        end
        imgui.SameLine()
        if imgui.Button("-") and current > field.min then
            newVal = NormalizeInteger(field, current - step)
            changed = newVal ~= current
        end
        imgui.SameLine()
        -- Cache the string on the field to avoid tostring allocation every frame
        if field._lastStepperVal ~= newVal then
            field._lastStepperStr = tostring(newVal)
            field._lastStepperVal = newVal
        end
        imgui.Text(field._lastStepperStr)
        imgui.SameLine()
        if imgui.Button("+") and current < field.max then
            newVal = NormalizeInteger(field, current + step)
            changed = newVal ~= current
        end
        return newVal, changed
    end,
}

FieldTypes.separator = {
    validate = function(field, prefix)
        if field.label ~= nil and type(field.label) ~= "string" then
            libWarn("%s: separator label must be string", prefix)
        end
    end,
    toHash = function()
        return ""
    end,
    fromHash = function()
        return nil
    end,
    toStaging = function()
        return nil
    end,
    draw = function(imgui, field)
        if field.label and field.label ~= "" then
            imgui.Separator()
            imgui.Text(field.label)
            imgui.Separator()
        else
            imgui.Separator()
        end
        return nil, false
    end,
}

public.FieldTypes = FieldTypes

-- Standalone framework debug toggle — hidden when Core is installed.
---@diagnostic disable-next-line: redundant-parameter
rom.gui.add_to_menu_bar(function()
    if next(_coordinators) ~= nil then return end
    if rom.ImGui.BeginMenu("adamant-lib") then
        local val, chg = rom.ImGui.Checkbox("Lib Debug", libConfig.DebugMode == true)
        if chg then libConfig.DebugMode = val end
        if rom.ImGui.IsItemHovered() then
            rom.ImGui.SetTooltip("Print lib-internal diagnostic warnings (schema errors, unknown field types)")
        end
        rom.ImGui.EndMenu()
    end
end)
