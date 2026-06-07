local deps = ...

local logging = deps.logging
local storage = deps.storage

local storageRefAdapter = {}

local function requireMethodSelf(context, self, expected)
    if self ~= expected then
        logging.violate("api.invalid_method_call", "%s must be called with ':' method syntax", context)
    end
end

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

function storageRefAdapter.create(opts)
    local root = opts.root
    local source = opts.source
    local isWritable = opts.writable == true
    local refs = {}

    return {
        get = function(alias)
            rejectPrivateAlias(source, alias)

            local cached = refs[alias]
            if cached ~= nil then
                return cached
            end

            local raw = root.get(alias)
            if raw == nil then
                return nil
            end

            local ref
            if storage.field.is(raw) then
                ref = wrapField(raw, source, isWritable)
            else
                ref = wrapTable(raw, source .. "(...)", isWritable)
            end
            refs[alias] = ref
            return ref
        end,
    }
end

storageRefAdapter.rejectPrivateAlias = rejectPrivateAlias

return storageRefAdapter
