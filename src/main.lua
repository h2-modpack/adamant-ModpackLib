-- =============================================================================
-- ADAMANT-LIB: Shared utilities for adamant standalone mods
-- =============================================================================
-- Access via: local lib = rom.mods['adamant-Modpack_Lib']
--
-- Provides:
--   backup, restore = lib.createBackupSystem()
--   local cb = lib.standaloneUI(def, config, apply, revert)  -- returns callback
--   rom.gui.add_to_menu_bar(cb)  -- caller registers in own plugin context
--   staging, snapshot, sync = lib.createSpecialState(config, schema)
--   lib.isEnabled(modConfig) — true if module AND master toggle are both on
--   lib.FieldTypes — central registry of field types (checkbox, dropdown, radio)
--   lib.drawField(imgui, field, value, width) — render a field widget
--   lib.encodeField(field, current, addBits)  — encode field into bit stream
--   lib.decodeField(field, readBits)          — decode field from bit stream

local mods = rom.mods
envy = mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN

-- Forward declaration — populated at bottom of file
local FieldTypes = {}

--- Check if a module should be active.
--- Returns true only if the module's own Enabled flag is true AND
--- the master toggle (ModEnabled) is true when Core is installed.
--- When Core is not installed, only the module's own flag is checked.
--- @param modConfig table  The module's chalk config (needs .Enabled)
--- @return boolean
function public.isEnabled(modConfig)
    local core = mods['adamant-Modpack_Core']
    if core and not core.config.ModEnabled then return false end
    return modConfig.Enabled == true
end

--- Print a diagnostic warning when Core's DebugMode is enabled.
--- Silent in production. Works with or without Core installed.
--- @param msg string  The warning message
function public.warn(msg)
    local core = mods['adamant-Modpack_Core']
    if core and core.config and core.config.DebugMode then
        print("[adamant] " .. msg)
    end
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
        for _, key in ipairs({...}) do
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
--- Skips rendering when adamant-Modpack_Core is installed.
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

    return function()
        if mods['adamant-Modpack_Core'] then return end
        if rom.ImGui.BeginMenu("adamant") then
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

            -- Inline options (when module is enabled)
            if modConfig.Enabled and def.options then
                imgui.Separator()
                for _, opt in ipairs(def.options) do
                    imgui.PushID(opt.configKey)
                    local newVal, chg = public.drawField(imgui, opt, modConfig[opt.configKey])
                    if chg then
                        modConfig[opt.configKey] = newVal
                        onOptionChanged()
                    end
                    imgui.PopID()
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

-- =============================================================================
-- FIELD TYPE DISPATCHERS
-- =============================================================================

--- Encode a single schema field into the bit stream.
--- @param field table       Field descriptor
--- @param current any       The current value to encode
--- @param addBits function  function(value, numBits)
function public.encodeField(field, current, addBits)
    local ft = FieldTypes[field.type]
    if ft then ft.encode(field, current, addBits)
    else public.warn("encodeField: unknown type '" .. tostring(field.type) .. "'") end
end

--- Decode a single schema field from the bit stream.
--- @param field table        Field descriptor
--- @param readBits function  function(numBits) -> number
--- @return any value
function public.decodeField(field, readBits)
    local ft = FieldTypes[field.type]
    if ft then return ft.decode(field, readBits) end
    public.warn("decodeField: unknown type '" .. tostring(field.type) .. "'")
    return nil
end

--- Render a schema field widget. Returns (newValue, changed).
--- @param imgui table       ImGui handle
--- @param field table       Field descriptor
--- @param value any         Current value
--- @param width number|nil  Optional pixel width for input fields
--- @return any newValue, boolean changed
function public.drawField(imgui, field, value, width)
    local ft = FieldTypes[field.type]
    if ft then return ft.draw(imgui, field, value, width) end
    public.warn("drawField: unknown type '" .. tostring(field.type) .. "'")
    return value, false
end

--- Validate a schema at declaration time. Warns via lib.warn (debug-guarded).
--- @param schema table   Ordered list of field descriptors
--- @param label string   Name shown in warnings (e.g. module name)
function public.validateSchema(schema, label)
    if type(schema) ~= "table" then
        public.warn(label .. ": schema is not a table")
        return
    end
    for i, field in ipairs(schema) do
        local prefix = label .. " field #" .. i
        if not field.configKey then
            public.warn(prefix .. ": missing configKey")
        end
        if not field.type then
            public.warn(prefix .. ": missing type")
        else
            local ft = FieldTypes[field.type]
            if not ft then
                public.warn(prefix .. ": unknown type '" .. tostring(field.type) .. "'")
            elseif ft.validate then
                ft.validate(field, prefix)
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
-- Returns: staging, snapshot, sync
--
--- @param modConfig table  The module's chalk config
--- @param schema table     Ordered list of field descriptors
--- @return table staging       Plain table mirroring config (fast reads/writes for UI)
--- @return function snapshot   Re-read config into staging (after profile load)
--- @return function sync       Flush staging to config (after UI edits)
function public.createSpecialState(modConfig, schema)
    public.validateSchema(schema, _PLUGIN.guid or "unknown module")

    local staging = {}

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
                writePath(staging, field.configKey, ft.toStaging(val))
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
    -- Public functions
    -- -----------------------------------------------------------------

    local function snapshot()
        copyConfigToStaging()
    end

    local function sync()
        copyStagingToConfig()
    end

    return staging, snapshot, sync
end

-- =============================================================================
-- FIELD TYPE REGISTRY
-- =============================================================================
-- Central definition of all schema field types. Each type declares its own:
--   bits(field)                        — number of bits for hashing
--   validate(field, prefix)            — declaration-time validation
--   encode(field, current, addBits)    — write value into bit stream
--   decode(field, readBits)            — read value from bit stream
--   toStaging(val)                     — transform value for staging table
--   draw(imgui, field, value, width)   — render widget, returns (newValue, changed)
--
-- To add a new type: add one entry here. All consumers dispatch automatically.

local function bitsRequired(n)
    if n <= 1 then return 1 end
    return math.ceil(math.log(n) / math.log(2))
end

FieldTypes.checkbox = {
    bits = function(field) return field.bits or 1 end,
    validate = function(field, prefix) end,
    encode = function(field, current, addBits)
        addBits(current and 1 or 0, 1)
    end,
    decode = function(field, readBits)
        return readBits(1) == 1
    end,
    toStaging = function(val) return val == true end,
    draw = function(imgui, field, value)
        if value == nil then value = field.default end
        return imgui.Checkbox(field.label or field.configKey, value or false)
    end,
}

FieldTypes.dropdown = {
    bits = function(field) return field.bits or bitsRequired(#(field.values or {})) end,
    validate = function(field, prefix)
        if not field.values then
            public.warn(prefix .. ": dropdown missing values list")
        elseif type(field.values) ~= "table" or #field.values == 0 then
            public.warn(prefix .. ": dropdown values must be a non-empty list")
        end
    end,
    encode = function(field, current, addBits)
        current = current or field.default or ""
        local bits = field.bits or bitsRequired(#(field.values or {}))
        local idx = 0
        for i, v in ipairs(field.values or {}) do
            if v == current then idx = i - 1; break end
        end
        addBits(idx, bits)
    end,
    decode = function(field, readBits)
        local bits = field.bits or bitsRequired(#(field.values or {}))
        local idx = readBits(bits)
        if field.values and idx < #field.values then
            return field.values[idx + 1]
        end
        return nil
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
        imgui.SameLine()
        if width then imgui.PushItemWidth(width) end
        local changed = false
        local newVal = current
        if imgui.BeginCombo("##field", preview) then
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
    bits = function(field) return field.bits or bitsRequired(#(field.values or {})) end,
    validate = function(field, prefix)
        if not field.values then
            public.warn(prefix .. ": radio missing values list")
        elseif type(field.values) ~= "table" or #field.values == 0 then
            public.warn(prefix .. ": radio values must be a non-empty list")
        end
    end,
    encode = function(field, current, addBits)
        current = current or field.default or ""
        local bits = field.bits or bitsRequired(#(field.values or {}))
        local idx = 0
        for i, v in ipairs(field.values or {}) do
            if v == current then idx = i - 1; break end
        end
        addBits(idx, bits)
    end,
    decode = function(field, readBits)
        local bits = field.bits or bitsRequired(#(field.values or {}))
        local idx = readBits(bits)
        if field.values and idx < #field.values then
            return field.values[idx + 1]
        end
        return nil
    end,
    toStaging = function(val) return val end,
    draw = function(imgui, field, value)
        local current = value or field.default or ""
        imgui.Text(field.label or field.configKey)
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

public.FieldTypes = FieldTypes
