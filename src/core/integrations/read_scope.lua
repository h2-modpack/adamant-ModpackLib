local deps = ...

local logging = deps.logging
local storage = deps.storage

local readScope = {}

local function requireMethodSelf(context, self, expected)
    if self ~= expected then
        logging.violate("api.invalid_method_call", "%s must be called with ':' method syntax", context)
    end
end

local function createAllowedSet(reads)
    local allowed = {}
    for _, alias in ipairs(reads or {}) do
        allowed[alias] = true
    end
    return allowed
end

local function packResults(...)
    return {
        n = select("#", ...),
        ...,
    }
end

function readScope.create(opts)
    local stagedState = opts.stagedState
    local context = opts.context or "integration"
    local allowed = createAllowedSet(opts.reads)
    local active = false
    local refs = {}
    local scope = {}

    local function requireActive()
        if not active then
            logging.violate("integrations.closed_scope", "%s: integration read scope is closed", context)
        end
    end

    local function requireAllowed(alias)
        if not allowed[alias] then
            logging.violate(
                "integrations.undeclared_read",
                "%s: undeclared integration read alias '%s'",
                context,
                tostring(alias))
        end
    end

    local function wrapField(rawField, contextSource, allowAlias)
        local field = {
            _kind = rawget(rawField, "_kind"),
        }
        local readContext = contextSource .. ":read"
        local readAliasContext = contextSource .. ":readAlias"
        local schemaContext = contextSource .. ":schema"
        local aliasContext = contextSource .. ":alias"
        local controlIdContext = contextSource .. ":controlId"

        function field.read(self, ...)
            requireMethodSelf(readContext, self, field)
            requireActive()
            return rawField:read(...)
        end

        function field.readAlias(self, alias)
            requireMethodSelf(readAliasContext, self, field)
            requireActive()
            if not allowAlias then
                requireAllowed(alias)
            end
            return rawField:readAlias(alias)
        end

        function field.schema(self)
            requireMethodSelf(schemaContext, self, field)
            requireActive()
            return rawField:schema()
        end

        function field.alias(self)
            requireMethodSelf(aliasContext, self, field)
            requireActive()
            return rawField:alias()
        end

        function field.controlId(self)
            requireMethodSelf(controlIdContext, self, field)
            requireActive()
            return rawField:controlId()
        end

        return field
    end

    local function wrapTable(rawTable, contextSource)
        local handle = {}
        local fields = {}
        local countContext = contextSource .. ":count"
        local readContext = contextSource .. ":read"
        local getContext = contextSource .. ":get"
        local snapshotContext = contextSource .. ":snapshot"
        local snapshotsContext = contextSource .. ":snapshots"

        function handle.count(self)
            requireMethodSelf(countContext, self, handle)
            requireActive()
            return rawTable:count()
        end

        function handle.read(self, rowIndex, rowAlias)
            requireMethodSelf(readContext, self, handle)
            requireActive()
            return rawTable:read(rowIndex, rowAlias)
        end

        function handle.get(self, rowIndex, rowAlias)
            requireMethodSelf(getContext, self, handle)
            requireActive()
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

            local field = wrapField(rawField, getContext, true)
            rowFields[rowAlias] = field
            return field
        end

        function handle.snapshot(self, rowIndex)
            requireMethodSelf(snapshotContext, self, handle)
            requireActive()
            return rawTable:snapshot(rowIndex)
        end

        function handle.snapshots(self)
            requireMethodSelf(snapshotsContext, self, handle)
            requireActive()
            return rawTable:snapshots()
        end

        return handle
    end

    local function getRef(alias)
        requireActive()
        requireAllowed(alias)

        local cached = refs[alias]
        if cached ~= nil then
            return cached
        end

        local raw = stagedState.get(alias)
        if raw == nil then
            return nil
        end

        local ref
        if storage.field.is(raw) then
            ref = wrapField(raw, context .. ".get", false)
        else
            ref = wrapTable(raw, context .. ".get(...)")
        end
        refs[alias] = ref
        return ref
    end

    function scope.read(alias, ...)
        local ref = getRef(alias)
        if ref == nil then
            return nil
        end
        return ref:read(...)
    end

    function scope.get(alias)
        return getRef(alias)
    end

    function scope.call(handler, ...)
        if active then
            logging.violate("integrations.nested_scope", "%s: integration read scope is already active", context)
        end

        active = true
        local args = {
            n = select("#", ...),
            ...,
        }
        local results = packResults(pcall(function()
            return handler(scope, table.unpack(args, 1, args.n))
        end))
        active = false
        if not results[1] then
            error(results[2], 0)
        end
        return table.unpack(results, 2, results.n)
    end

    return scope
end

return readScope
