local deps = ...

local logging = deps.logging
local values = deps.values
local storage = deps.storage
local requireMethodSelf = deps.requireMethodSelf

local refs = {}
local CONTROL_REF_MARKER = {}

-- Bindings are compiler-built (`controls/compiler.lua`): every binding has `key`/`alias`;
-- `bitAliases`/`bitKeysByAlias` exist only for packed fields, `rowAliases`/`rowBindings` only
-- for table fields.

local function toSemanticBitAlias(binding, internalAlias)
    local semanticAlias = binding.bitKeysByAlias and binding.bitKeysByAlias[internalAlias]
    return semanticAlias or internalAlias
end

local function semanticFieldSchema(rawSchema, binding)
    local schema = values.deepCopy(rawSchema)
    schema.alias = binding.key
    schema._packedAliasViews = nil
    if type(schema.bits) == "table" then
        for _, bit in ipairs(schema.bits) do
            bit.alias = toSemanticBitAlias(binding, bit.alias)
        end
    end
    if type(schema._bitAliases) == "table" then
        for _, bit in ipairs(schema._bitAliases) do
            bit.alias = toSemanticBitAlias(binding, bit.alias)
        end
    end
    return schema
end

local function mapFieldAlias(binding, alias, context)
    local internalAlias = binding.bitAliases and binding.bitAliases[alias]
    if internalAlias == nil then
        logging.violate("controls.unknown_field_alias", "%s: unknown control field alias '%s'",
            tostring(context), tostring(alias))
    end
    return internalAlias
end

local function mapRowAlias(binding, alias, context)
    local internalAlias = binding.rowAliases and binding.rowAliases[alias]
    if internalAlias == nil then
        logging.violate("controls.unknown_field_alias", "%s: unknown control table row alias '%s'",
            tostring(context), tostring(alias))
    end
    return internalAlias
end

local function wrapField(rawField, binding, writable)
    local field = {
        _kind = rawget(rawField, "_kind"),
    }

    function field.read(self, ...)
        requireMethodSelf("control field read", self, field)
        return rawField:read(...)
    end

    function field.readAlias(self, alias)
        requireMethodSelf("control field readAlias", self, field)
        return rawField:readAlias(mapFieldAlias(binding, alias, "control field readAlias"))
    end

    function field.schema(self)
        requireMethodSelf("control field schema", self, field)
        return semanticFieldSchema(rawField:schema(), binding)
    end

    function field.alias(self)
        requireMethodSelf("control field alias", self, field)
        return rawField:alias()
    end

    function field.controlId(self)
        requireMethodSelf("control field controlId", self, field)
        return rawField:controlId()
    end

    if writable then
        function field.write(self, value)
            requireMethodSelf("control field write", self, field)
            return rawField:write(value)
        end

        function field.writeAlias(self, alias, value)
            requireMethodSelf("control field writeAlias", self, field)
            return rawField:writeAlias(mapFieldAlias(binding, alias, "control field writeAlias"), value)
        end

        function field.reset(self)
            requireMethodSelf("control field reset", self, field)
            return rawField:reset()
        end
    end

    return field
end

local function translateRowValues(binding, rowValues)
    if type(rowValues) ~= "table" then
        return rowValues
    end
    local mapped = {}
    for key, value in pairs(rowValues) do
        mapped[mapRowAlias(binding, key, "control table row values")] = value
    end
    return mapped
end

local function translateSnapshot(binding, snapshot)
    if type(snapshot) ~= "table" then
        return snapshot
    end
    local mapped = {}
    for key, internalAlias in pairs(binding.rowAliases or {}) do
        mapped[key] = values.deepCopy(snapshot[internalAlias])
    end
    return mapped
end

local function wrapTable(rawTable, binding, writable)
    local handle = {}
    local fieldCache = {}

    local function clearFieldCache()
        fieldCache = {}
    end

    function handle.count(self)
        requireMethodSelf("control table count", self, handle)
        return rawTable:count()
    end

    function handle.read(self, rowIndex, rowAlias)
        requireMethodSelf("control table read", self, handle)
        return rawTable:read(rowIndex, mapRowAlias(binding, rowAlias, "control table read"))
    end

    function handle.get(self, rowIndex, rowAlias)
        requireMethodSelf("control table get", self, handle)
        rowIndex = math.floor(tonumber(rowIndex) or 0)
        local internalAlias = mapRowAlias(binding, rowAlias, "control table get")
        local rowFields = fieldCache[rowIndex]
        if not rowFields then
            rowFields = {}
            fieldCache[rowIndex] = rowFields
        end
        local cached = rowFields[internalAlias]
        if cached then
            return cached
        end
        local rawField = rawTable:get(rowIndex, internalAlias)
        if rawField == nil then
            return nil
        end
        local field = wrapField(rawField, binding.rowBindings[rowAlias], writable)
        rowFields[internalAlias] = field
        return field
    end

    function handle.snapshot(self, rowIndex)
        requireMethodSelf("control table snapshot", self, handle)
        return translateSnapshot(binding, rawTable:snapshot(rowIndex))
    end

    function handle.snapshots(self)
        requireMethodSelf("control table snapshots", self, handle)
        local snapshots = {}
        for index, snapshot in ipairs(rawTable:snapshots()) do
            snapshots[index] = translateSnapshot(binding, snapshot)
        end
        return snapshots
    end

    if writable then
        function handle.write(self, rowIndex, rowAlias, value)
            requireMethodSelf("control table write", self, handle)
            return rawTable:write(rowIndex, mapRowAlias(binding, rowAlias, "control table write"), value)
        end

        function handle.reset(self, rowIndex, rowAlias)
            requireMethodSelf("control table reset", self, handle)
            return rawTable:reset(rowIndex, mapRowAlias(binding, rowAlias, "control table reset"))
        end

        function handle.append(self, rowValues)
            requireMethodSelf("control table append", self, handle)
            local changed = rawTable:append(translateRowValues(binding, rowValues))
            if changed then clearFieldCache() end
            return changed
        end

        function handle.insert(self, rowIndex, rowValues)
            requireMethodSelf("control table insert", self, handle)
            local changed = rawTable:insert(rowIndex, translateRowValues(binding, rowValues))
            if changed then clearFieldCache() end
            return changed
        end

        function handle.remove(self, rowIndex)
            requireMethodSelf("control table remove", self, handle)
            local changed = rawTable:remove(rowIndex)
            if changed then clearFieldCache() end
            return changed
        end

        function handle.clear(self)
            requireMethodSelf("control table clear", self, handle)
            local changed = rawTable:clear()
            if changed then clearFieldCache() end
            return changed
        end
    end

    return handle
end

local function createFieldSet(root, entry, surface, writable)
    local unavailable = {}
    local fields = setmetatable({}, {
        __index = function(_, key)
            local reason = unavailable[key]
            if reason ~= nil then
                logging.violate("controls.unavailable_field", "control '%s': field '%s' is unavailable in %s",
                    tostring(entry.name),
                    tostring(key),
                    reason)
            end
            return nil
        end,
    })

    for key, binding in pairs(entry.bindings) do
        local schema = root.getAliasSchema(binding.alias)
        if schema == nil then
            logging.violate("controls.invalid_field", "control '%s': compiled field '%s' is missing",
                tostring(entry.name), tostring(key))
        else
            local bindField = true
            if surface == "runtime" and not schema._persist then
                bindField = false
                unavailable[key] = "runtime because it is UI-only transient storage"
            end

            if bindField then
                local raw = root.get(binding.alias)
                if raw == nil then
                    logging.violate("controls.invalid_field", "control '%s': compiled field '%s' is missing",
                        tostring(entry.name), tostring(key))
                elseif storage.field.is(raw) then
                    fields[key] = wrapField(raw, binding, writable)
                else
                    fields[key] = wrapTable(raw, binding, writable)
                end
            end
        end
    end

    return fields
end

local function attachControlInternals(control, entry, surface)
    control[CONTROL_REF_MARKER] = {
        entry = entry,
        surface = surface,
    }

    if control.name == nil then
        control.name = function()
            return entry.name
        end
    end
    if control.kind == nil then
        control.kind = function()
            return entry.templateName
        end
    end

    return control
end

local function createControl(entry, fields, surface)
    local factory = surface == "ui" and entry.template.createUi or entry.template.createRuntime
    local control
    if factory ~= nil then
        control = factory(fields, entry.instance)
    else
        control = {}
    end
    if type(control) ~= "table" then
        logging.violate("controls.invalid_template", "control '%s': template factory must return a table",
            tostring(entry.name))
    end
    return attachControlInternals(control, entry, surface)
end

local function resetBoundRoots(root, entry)
    local changedCount = 0
    local seen = {}

    for _, binding in pairs(entry.bindings) do
        local alias = binding.alias
        if alias ~= nil and not seen[alias] then
            seen[alias] = true
            local schema = root.getAliasSchema(alias)
            if schema == nil then
                logging.violate("controls.invalid_field", "control '%s': compiled field '%s' is missing",
                    tostring(entry.name), tostring(binding.key))
            else
                local current = root.read(alias)
                if not storage.valuesEqual(schema, current, schema.default) then
                    root.reset(alias)
                    changedCount = changedCount + 1
                end
            end
        end
    end

    return changedCount > 0, changedCount
end

---@param root table Persistent state (runtime surface) or staged view (UI surface).
---@param catalog table Compiled control catalog (`compiler.compile(...).catalog`).
---@param surface "runtime"|"ui"
local function createFacade(root, catalog, surface)
    local writable = surface == "ui"
    local controlCache = {}
    local facade = {}

    function facade.get(name)
        local entry = catalog.instances[name]
        if entry == nil then
            logging.violate("controls.unknown_control", "%s.controls.get: unknown control '%s'",
                surface == "ui" and "ui" or "runtime", tostring(name))
        end
        local cached = controlCache[name]
        if cached ~= nil then
            return cached
        end
        local fields = createFieldSet(root, entry, surface, writable)
        local control = createControl(entry, fields, surface)
        controlCache[name] = control
        return control
    end

    function facade.read(name, ...)
        local control = facade.get(name)
        if type(control.read) ~= "function" then
            logging.violate("controls.invalid_template", "control '%s' does not expose read()", tostring(name))
        end
        return control:read(...)
    end

    if surface == "ui" then
        function facade.reset(name)
            local entry = catalog.instances[name]
            if entry == nil then
                logging.violate("controls.unknown_control", "ui.controls.reset: unknown control '%s'", tostring(name))
            end
            return resetBoundRoots(root, entry)
        end
    end

    return facade
end

function refs.createRuntime(persistentState, catalog)
    return createFacade(persistentState, catalog, "runtime")
end

function refs.createUi(stagedState, catalog)
    return createFacade(stagedState, catalog, "ui")
end

function refs.getEntry(value)
    if type(value) ~= "table" then
        return nil
    end
    local marker = rawget(value, CONTROL_REF_MARKER)
    return type(marker) == "table" and marker.entry or nil
end

function refs.getSurface(value)
    if type(value) ~= "table" then
        return nil
    end
    local marker = rawget(value, CONTROL_REF_MARKER)
    return type(marker) == "table" and marker.surface or nil
end

return refs
