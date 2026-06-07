local deps = ...

local logging = deps.logging
local values = deps.values
local storage = deps.storage
local phaseGate = deps.phaseGate

local refs = {}
local CONTROL_REF_MARKER = {}

local function requireSelf(context, self, expected)
    if self ~= expected then
        logging.violate("api.invalid_method_call", "%s must be called with ':' method syntax", context)
    end
end

local function createGate(phase)
    if phase == "draw" then
        return phaseGate.requireAnyDraw
    end
    return phaseGate.requireRuntime
end

local function findMappedAlias(mapping, alias)
    if type(mapping) ~= "table" then
        return nil
    end
    return mapping[alias]
end

local function toSemanticAlias(mapping, internalAlias)
    if type(mapping) ~= "table" then
        return internalAlias
    end
    for semanticAlias, mappedAlias in pairs(mapping) do
        if mappedAlias == internalAlias then
            return semanticAlias
        end
    end
    return internalAlias
end

local function semanticFieldSchema(rawSchema, binding)
    local schema = values.deepCopy(rawSchema)
    if binding == nil then
        return schema
    end
    schema.alias = binding.key or schema.alias
    schema._packedAliasViews = nil
    if type(schema.bits) == "table" then
        for _, bit in ipairs(schema.bits) do
            bit.alias = toSemanticAlias(binding.bitAliases, bit.alias)
        end
    end
    if type(schema._bitAliases) == "table" then
        for _, bit in ipairs(schema._bitAliases) do
            bit.alias = toSemanticAlias(binding.bitAliases, bit.alias)
        end
    end
    return schema
end

local function mapFieldAlias(binding, alias, context)
    local internalAlias = findMappedAlias(binding and binding.bitAliases or nil, alias)
    if internalAlias == nil then
        logging.violate("controls.unknown_field_alias", "%s: unknown control field alias '%s'",
            tostring(context), tostring(alias))
    end
    return internalAlias
end

local function mapRowAlias(binding, alias, context)
    local internalAlias = findMappedAlias(binding and binding.rowAliases or nil, alias)
    if internalAlias == nil then
        logging.violate("controls.unknown_field_alias", "%s: unknown control table row alias '%s'",
            tostring(context), tostring(alias))
    end
    return internalAlias
end

local function wrapField(rawField, binding, gate, writable)
    local field = {
        _kind = rawget(rawField, "_kind"),
    }

    function field.read(self, ...)
        requireSelf("control field read", self, field)
        return rawField:read(...)
    end

    function field.readAlias(self, alias)
        requireSelf("control field readAlias", self, field)
        return rawField:readAlias(mapFieldAlias(binding, alias, "control field readAlias"))
    end

    function field.schema(self)
        requireSelf("control field schema", self, field)
        return semanticFieldSchema(rawField:schema(), binding)
    end

    function field.alias(self)
        requireSelf("control field alias", self, field)
        return rawField:alias()
    end

    function field.controlId(self)
        requireSelf("control field controlId", self, field)
        return rawField:controlId()
    end

    if writable then
        function field.write(self, value)
            requireSelf("control field write", self, field)
            gate()
            return rawField:write(value)
        end

        function field.writeAlias(self, alias, value)
            requireSelf("control field writeAlias", self, field)
            gate()
            return rawField:writeAlias(mapFieldAlias(binding, alias, "control field writeAlias"), value)
        end

        function field.reset(self)
            requireSelf("control field reset", self, field)
            gate()
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

local function wrapTable(rawTable, binding, gate, writable)
    local handle = {}
    local fieldCache = {}

    local function clearFieldCache()
        fieldCache = {}
    end

    function handle.count(self)
        requireSelf("control table count", self, handle)
        return rawTable:count()
    end

    function handle.read(self, rowIndex, rowAlias)
        requireSelf("control table read", self, handle)
        return rawTable:read(rowIndex, mapRowAlias(binding, rowAlias, "control table read"))
    end

    function handle.get(self, rowIndex, rowAlias)
        requireSelf("control table get", self, handle)
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
        local field = wrapField(rawField, binding.rowBindings and binding.rowBindings[rowAlias] or nil, gate, writable)
        rowFields[internalAlias] = field
        return field
    end

    function handle.snapshot(self, rowIndex)
        requireSelf("control table snapshot", self, handle)
        return translateSnapshot(binding, rawTable:snapshot(rowIndex))
    end

    function handle.snapshots(self)
        requireSelf("control table snapshots", self, handle)
        local snapshots = {}
        for index, snapshot in ipairs(rawTable:snapshots()) do
            snapshots[index] = translateSnapshot(binding, snapshot)
        end
        return snapshots
    end

    if writable and type(rawTable.write) == "function" then
        function handle.write(self, rowIndex, rowAlias, value)
            requireSelf("control table write", self, handle)
            gate()
            return rawTable:write(rowIndex, mapRowAlias(binding, rowAlias, "control table write"), value)
        end

        function handle.reset(self, rowIndex, rowAlias)
            requireSelf("control table reset", self, handle)
            gate()
            return rawTable:reset(rowIndex, mapRowAlias(binding, rowAlias, "control table reset"))
        end

        function handle.append(self, rowValues)
            requireSelf("control table append", self, handle)
            gate()
            local changed = rawTable:append(translateRowValues(binding, rowValues))
            if changed then clearFieldCache() end
            return changed
        end

        function handle.insert(self, rowIndex, rowValues)
            requireSelf("control table insert", self, handle)
            gate()
            local changed = rawTable:insert(rowIndex, translateRowValues(binding, rowValues))
            if changed then clearFieldCache() end
            return changed
        end

        function handle.remove(self, rowIndex)
            requireSelf("control table remove", self, handle)
            gate()
            local changed = rawTable:remove(rowIndex)
            if changed then clearFieldCache() end
            return changed
        end

        function handle.clear(self)
            requireSelf("control table clear", self, handle)
            gate()
            local changed = rawTable:clear()
            if changed then clearFieldCache() end
            return changed
        end
    end

    return handle
end

local function createFieldSet(root, entry, phase, writable)
    local gate = createGate(phase)
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

    for key, binding in pairs(entry.bindings or {}) do
        local schema = root.getAliasSchema(binding.alias)
        if schema == nil then
            logging.violate("controls.invalid_field", "control '%s': compiled field '%s' is missing",
                tostring(entry.name), tostring(key))
        else
            local bindField = true
            if phase == "runtime" and not schema._persist then
                bindField = false
                unavailable[key] = "runtime because it is UI-only transient storage"
            end

            if bindField then
                local raw = root.get(binding.alias)
                if raw == nil then
                    logging.violate("controls.invalid_field", "control '%s': compiled field '%s' is missing",
                        tostring(entry.name), tostring(key))
                elseif storage.field.is(raw) then
                    fields[key] = wrapField(raw, binding, gate, writable)
                else
                    fields[key] = wrapTable(raw, binding, gate, writable)
                end
            end
        end
    end

    return fields
end

local function attachControlInternals(control, entry, phase)
    control[CONTROL_REF_MARKER] = {
        entry = entry,
        phase = phase,
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

local function createControl(entry, fields, factoryPhase)
    local factory = factoryPhase == "draw" and entry.template.createUi or entry.template.createRuntime
    local control
    if type(factory) == "function" then
        control = factory(fields, entry.instance)
    else
        control = {}
    end
    if type(control) ~= "table" then
        logging.violate("controls.invalid_template", "control '%s': template factory must return a table",
            tostring(entry.name))
    end
    return attachControlInternals(control, entry, factoryPhase)
end

local function resetBoundRoots(root, entry)
    local changedCount = 0
    local seen = {}

    for _, binding in pairs(entry.bindings or {}) do
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

local function createFacade(opts)
    local catalog = opts.catalog or {}
    local phase = opts.phase
    local factoryPhase = opts.factoryPhase or phase
    local root = opts.root
    local writable = opts.writable == true or phase == "draw"
    local controlCache = {}
    local facade = {}

    function facade.get(name)
        local entry = catalog.instances and catalog.instances[name] or nil
        if entry == nil then
            logging.violate("controls.unknown_control", "%s.controls.get: unknown control '%s'",
                phase == "draw" and "ui" or "runtime", tostring(name))
        end
        local cached = controlCache[name]
        if cached ~= nil then
            return cached
        end
        local fields = createFieldSet(root, entry, phase, writable)
        local control = createControl(entry, fields, factoryPhase)
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

    if phase == "draw" then
        function facade.reset(name)
            phaseGate.requireAnyDraw()
            local entry = catalog.instances and catalog.instances[name] or nil
            if entry == nil then
                logging.violate("controls.unknown_control", "ui.controls.reset: unknown control '%s'", tostring(name))
            end
            return resetBoundRoots(root, entry)
        end

    end

    return facade
end

function refs.createRuntime(persistentState, catalog)
    return createFacade({
        root = persistentState,
        catalog = catalog,
        phase = "runtime",
    })
end

function refs.createUi(stagedState, catalog)
    return createFacade({
        root = stagedState,
        catalog = catalog,
        phase = "draw",
    })
end

function refs.isControl(value)
    return type(value) == "table" and rawget(value, CONTROL_REF_MARKER) ~= nil
end

function refs.getEntry(value)
    if type(value) ~= "table" then
        return nil
    end
    local marker = rawget(value, CONTROL_REF_MARKER)
    return type(marker) == "table" and marker.entry or nil
end

function refs.getPhase(value)
    if type(value) ~= "table" then
        return nil
    end
    local marker = rawget(value, CONTROL_REF_MARKER)
    return type(marker) == "table" and marker.phase or nil
end

return refs
