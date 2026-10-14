local deps = ...

local logging = deps.logging
local storage = deps.storage
local requireMethodSelf = deps.requireMethodSelf

local storageRefAdapter = {}

local function rejectPrivateAlias(context, alias)
    if storage.isPrivateAlias(alias) then
        logging.violate(
            "storage.private_alias",
            "%s: private Lib storage alias '%s' is not author-accessible",
            context,
            tostring(alias)
        )
    end
end

local function wrapField(rawField, contextSource, isWritable)
    local field = {
        _kind = rawget(rawField, "_kind"),
    }
    local readContext = contextSource .. ":read"
    local readAliasContext = contextSource .. ":readAlias"
    local writeContext = contextSource .. ":write"
    local writeAliasContext = contextSource .. ":writeAlias"
    local resetContext = contextSource .. ":reset"
    local schemaContext = contextSource .. ":schema"
    local aliasContext = contextSource .. ":alias"
    local controlIdContext = contextSource .. ":controlId"

    function field.read(self, ...)
        requireMethodSelf(readContext, self, field)
        return rawField:read(...)
    end

    function field.readAlias(self, alias)
        requireMethodSelf(readAliasContext, self, field)
        rejectPrivateAlias(readAliasContext, alias)
        return rawField:readAlias(alias)
    end

    function field.schema(self)
        requireMethodSelf(schemaContext, self, field)
        return rawField:schema()
    end

    function field.alias(self)
        requireMethodSelf(aliasContext, self, field)
        return rawField:alias()
    end

    function field.controlId(self)
        requireMethodSelf(controlIdContext, self, field)
        return rawField:controlId()
    end

    if isWritable then
        function field.write(self, value)
            requireMethodSelf(writeContext, self, field)
            return rawField:write(value)
        end

        function field.writeAlias(self, alias, value)
            requireMethodSelf(writeAliasContext, self, field)
            rejectPrivateAlias(writeAliasContext, alias)
            return rawField:writeAlias(alias, value)
        end

        function field.reset(self)
            requireMethodSelf(resetContext, self, field)
            return rawField:reset()
        end
    end

    return field
end

local function wrapTable(rawTable, contextSource, isWritable)
    local handle = {}
    local fields = {}

    local function clearFieldCache()
        fields = {}
    end

    local countContext = contextSource .. ":count"
    local readContext = contextSource .. ":read"
    local getContext = contextSource .. ":get"
    local snapshotContext = contextSource .. ":snapshot"
    local snapshotsContext = contextSource .. ":snapshots"
    local writeContext = contextSource .. ":write"
    local resetContext = contextSource .. ":reset"
    local appendContext = contextSource .. ":append"
    local insertContext = contextSource .. ":insert"
    local removeContext = contextSource .. ":remove"
    local clearContext = contextSource .. ":clear"

    function handle.count(self)
        requireMethodSelf(countContext, self, handle)
        return rawTable:count()
    end

    function handle.read(self, rowIndex, rowAlias)
        requireMethodSelf(readContext, self, handle)
        rejectPrivateAlias(readContext, rowAlias)
        return rawTable:read(rowIndex, rowAlias)
    end

    function handle.get(self, rowIndex, rowAlias)
        requireMethodSelf(getContext, self, handle)
        rejectPrivateAlias(getContext, rowAlias)
        rowIndex = math.floor(tonumber(rowIndex) or 0)
        local rowFields = fields[rowIndex]
        if not rowFields then
            rowFields = {}
            fields[rowIndex] = rowFields
        end

        local cached = rowFields[rowAlias]
        if cached then
            return cached
        end

        local rawField = rawTable:get(rowIndex, rowAlias)
        if rawField == nil then
            return nil
        end

        local field = wrapField(rawField, contextSource .. ":get", isWritable)
        rowFields[rowAlias] = field
        return field
    end

    function handle.snapshot(self, rowIndex)
        requireMethodSelf(snapshotContext, self, handle)
        return rawTable:snapshot(rowIndex)
    end

    function handle.snapshots(self)
        requireMethodSelf(snapshotsContext, self, handle)
        return rawTable:snapshots()
    end

    if isWritable and type(rawTable.write) == "function" then
        function handle.write(self, rowIndex, rowAlias, value)
            requireMethodSelf(writeContext, self, handle)
            rejectPrivateAlias(writeContext, rowAlias)
            return rawTable:write(rowIndex, rowAlias, value)
        end

        function handle.reset(self, rowIndex, rowAlias)
            requireMethodSelf(resetContext, self, handle)
            rejectPrivateAlias(resetContext, rowAlias)
            return rawTable:reset(rowIndex, rowAlias)
        end

        function handle.append(self, rowValues)
            requireMethodSelf(appendContext, self, handle)
            local changed = rawTable:append(rowValues)
            if changed then clearFieldCache() end
            return changed
        end

        function handle.insert(self, rowIndex, rowValues)
            requireMethodSelf(insertContext, self, handle)
            local changed = rawTable:insert(rowIndex, rowValues)
            if changed then clearFieldCache() end
            return changed
        end

        function handle.remove(self, rowIndex)
            requireMethodSelf(removeContext, self, handle)
            local changed = rawTable:remove(rowIndex)
            if changed then clearFieldCache() end
            return changed
        end

        function handle.clear(self)
            requireMethodSelf(clearContext, self, handle)
            local changed = rawTable:clear()
            if changed then clearFieldCache() end
            return changed
        end
    end

    return handle
end

---Build one author-facing storage lane over a state-owned root.
---The root owns alias/mode validation; the lane owns private-alias rejection,
---method-syntax wrapping, and read-only projection. `fields` are attached to the
---lane at construction (for example `cache`/`shared`/`controls` on `runtime.data`).
---@param opts { get: fun(alias: string, context: string): table?, source: string, writable?: boolean,
---    resetRoot?: fun(alias: string): boolean, fields?: table<string, any> }
---@return table lane
function storageRefAdapter.createLane(opts)
    local rootGet = opts.get
    local source = opts.source
    local getContext = source .. ".get"
    local isWritable = opts.writable == true
    local resetRoot = opts.resetRoot
    local refs = {}
    local lane = {}
    for key, value in pairs(opts.fields or {}) do
        lane[key] = value
    end

    function lane.get(alias)
        rejectPrivateAlias(getContext, alias)

        local cached = refs[alias]
        if cached ~= nil then
            return cached
        end

        local raw = rootGet(alias, getContext)
        if raw == nil then
            return nil
        end

        local ref
        if storage.field.is(raw) then
            ref = wrapField(raw, getContext, isWritable)
        else
            ref = wrapTable(raw, getContext .. "(...)", isWritable)
        end
        refs[alias] = ref
        return ref
    end

    function lane.read(alias, ...)
        local ref = lane.get(alias)
        if ref == nil then
            return nil
        end
        return ref:read(...)
    end

    if isWritable then
        function lane.write(alias, ...)
            local ref = lane.get(alias)
            if ref == nil then
                return nil
            end
            return ref:write(...)
        end
    end

    if resetRoot ~= nil then
        local resetContext = source .. ".reset"
        function lane.reset(alias, ...)
            if select("#", ...) == 0 then
                -- `resetRoot` resolves and validates the alias itself.
                rejectPrivateAlias(resetContext, alias)
                return resetRoot(alias)
            end
            local ref = lane.get(alias)
            if ref == nil then
                return nil
            end
            return ref:reset(...)
        end
    end

    return lane
end

return storageRefAdapter
