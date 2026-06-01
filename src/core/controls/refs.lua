local deps = ...

local logging = deps.logging
local values = deps.values
local storage = deps.storage
local phaseGate = deps.phaseGate
local actionRefs = deps.actionRefs

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

local function mapAlias(binding, alias)
    if binding == nil then
        return alias
    end
    if binding.rowAliases and binding.rowAliases[alias] then
        return binding.rowAliases[alias]
    end
    if binding.bitAliases and binding.bitAliases[alias] then
        return binding.bitAliases[alias]
    end
    return alias
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
        return rawField:readAlias(mapAlias(binding, alias))
    end

    function field.schema(self)
        requireSelf("control field schema", self, field)
        return rawField:schema()
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
            return rawField:writeAlias(mapAlias(binding, alias), value)
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
        mapped[mapAlias(binding, key)] = value
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
        return rawTable:read(rowIndex, mapAlias(binding, rowAlias))
    end

    function handle.get(self, rowIndex, rowAlias)
        requireSelf("control table get", self, handle)
        rowIndex = math.floor(tonumber(rowIndex) or 0)
        local internalAlias = mapAlias(binding, rowAlias)
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
            return rawTable:write(rowIndex, mapAlias(binding, rowAlias), value)
        end

        function handle.reset(self, rowIndex, rowAlias)
            requireSelf("control table reset", self, handle)
            gate()
            return rawTable:reset(rowIndex, mapAlias(binding, rowAlias))
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
    local fields = {}

    for key, binding in pairs(entry.bindings or {}) do
        local raw = root.get(binding.alias)
        if raw == nil then
            logging.violate("controls.invalid_field", "control '%s': compiled field '%s' is missing",
                tostring(entry.name), tostring(key))
        end
        if storage.field.is(raw) then
            fields[key] = wrapField(raw, binding, gate, writable)
        else
            fields[key] = wrapTable(raw, binding, gate, writable)
        end
    end

    return fields
end

local function attachControlInternals(control, entry, gate, actionBuffer)
    control[CONTROL_REF_MARKER] = entry

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

    if actionBuffer ~= nil then
        local commandRefs = {}
        function control:command(commandName)
            requireSelf("control:command", self, control)
            gate()
            local actionKey = entry.commands and entry.commands[commandName] or nil
            if actionKey == nil then
                logging.violate("controls.unknown_command", "control '%s': unknown command '%s'",
                    tostring(entry.name), tostring(commandName))
            end
            local ref = commandRefs[commandName]
            if ref ~= nil then
                return ref
            end
            ref = actionRefs.createInternalDrawActionRef(actionBuffer, actionKey, phaseGate)
            commandRefs[commandName] = ref
            return ref
        end
    end

    return control
end

local function createControl(entry, fields, phase, actionBuffer)
    local factory = phase == "draw" and entry.template.createUi or entry.template.createRuntime
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
    return attachControlInternals(control, entry, createGate(phase), actionBuffer)
end

local function createFacade(opts)
    local catalog = opts.catalog or {}
    local phase = opts.phase
    local root = opts.root
    local actionBuffer = opts.actionBuffer
    local writable = phase == "draw"
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
        local control = createControl(entry, fields, phase, actionBuffer)
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

    return facade
end

function refs.createRuntime(persistentState, catalog)
    return createFacade({
        root = persistentState,
        catalog = catalog,
        phase = "runtime",
    })
end

function refs.createUi(stagedState, catalog, actionBuffer)
    return createFacade({
        root = stagedState,
        catalog = catalog,
        phase = "draw",
        actionBuffer = actionBuffer,
    })
end

function refs.isControl(value)
    return type(value) == "table" and rawget(value, CONTROL_REF_MARKER) ~= nil
end

function refs.getEntry(value)
    if type(value) ~= "table" then
        return nil
    end
    return rawget(value, CONTROL_REF_MARKER)
end

return refs
