local deps = ...

local logging = deps.logging
local phaseGate = deps.phaseGate
local storage = deps.storage

local storageRefAdapter = {}

local function requireMethodSelf(context, self, expected)
    if self ~= expected then
        logging.violate("api.invalid_method_call", "%s must be called with ':' method syntax", context)
    end
end

---@param opts table
---@return table
function storageRefAdapter.create(opts)
    local root = opts.root
    local phaseOwner = opts.phaseOwner
    local source = opts.source
    local tableSource = source .. "(...)"
    local isDrawPhase = opts.phase == "draw"
    local isWritable = opts.writable == true
    local refs = {}
    local fieldOwnerToken = {}

    local fieldOwner = {
        read = function(alias)
            return root.read(alias)
        end,
        getAliasSchema = function(alias)
            return root.getAliasSchema(alias)
        end,
    }

    if isWritable then
        fieldOwner.write = function(alias, value)
            return root.write(alias, value)
        end
        fieldOwner.reset = function(alias)
            return root.reset(alias)
        end
    end

    local function getSchema(alias)
        local node = type(alias) == "string" and root.getAliasSchema(alias) or nil
        if not node then
            return root.get(alias)
        end
        return node
    end

    local function createFieldWrapper(rawField, contextSource, ownerToken)
        local readContext = contextSource .. ":read"
        local readAliasContext = contextSource .. ":readAlias"
        local writeContext = contextSource .. ":write"
        local writeAliasContext = contextSource .. ":writeAlias"
        local resetContext = contextSource .. ":reset"
        local schemaContext = contextSource .. ":schema"
        local aliasContext = contextSource .. ":alias"
        local controlIdContext = contextSource .. ":controlId"
        local ownerContext = contextSource .. ":owner"
        local field
        field = {
            _kind = rawget(rawField, "_kind"),
            read = function(self, ...)
                requireMethodSelf(readContext, self, field)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                return rawField:read(...)
            end,
            readAlias = function(self, alias)
                requireMethodSelf(readAliasContext, self, field)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                return rawField:readAlias(alias)
            end,
            write = function(self, value)
                requireMethodSelf(writeContext, self, field)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                return rawField:write(value)
            end,
            writeAlias = function(self, alias, value)
                requireMethodSelf(writeAliasContext, self, field)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                return rawField:writeAlias(alias, value)
            end,
            reset = function(self)
                requireMethodSelf(resetContext, self, field)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                return rawField:reset()
            end,
            schema = function(self)
                requireMethodSelf(schemaContext, self, field)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                return rawField:schema()
            end,
            alias = function(self)
                requireMethodSelf(aliasContext, self, field)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                return rawField:alias()
            end,
            controlId = function(self)
                requireMethodSelf(controlIdContext, self, field)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                return rawField:controlId()
            end,
            owner = function(self)
                requireMethodSelf(ownerContext, self, field)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                return ownerToken
            end,
        }
        return field
    end

    local function createField(alias, node)
        local rawField = storage.field.createKnown(fieldOwner, alias, node, source)
        return createFieldWrapper(rawField, source, fieldOwnerToken)
    end

    local function createTable(alias, node)
        local raw = root.table(alias)
        local rowAliasNodes = storage.getAliases(node.row)
        local rowFields = {}
        local rowControlIds = {}
        local rowOwnerTokens = {}
        local handle = {}
        local countContext = tableSource .. ":count"
        local readContext = tableSource .. ":read"
        local writeContext = tableSource .. ":write"
        local resetContext = tableSource .. ":reset"
        local getContext = tableSource .. ":get"
        local snapshotContext = tableSource .. ":snapshot"
        local snapshotsContext = tableSource .. ":snapshots"
        local appendContext = tableSource .. ":append"
        local insertContext = tableSource .. ":insert"
        local removeContext = tableSource .. ":remove"
        local clearContext = tableSource .. ":clear"

        local function clearRowStructureCaches()
            rowFields = {}
            rowControlIds = {}
            rowOwnerTokens = {}
        end

        local function getRowFieldControlId(rowIndex, rowAlias)
            rowIndex = math.floor(tonumber(rowIndex) or 0)
            local rowIds = rowControlIds[rowIndex]
            if not rowIds then
                rowIds = {}
                rowControlIds[rowIndex] = rowIds
            end

            local id = rowIds[rowAlias]
            if not id then
                id = tostring(alias) .. ":" .. tostring(rowIndex) .. ":" .. tostring(rowAlias)
                rowIds[rowAlias] = id
            end
            return id
        end

        local function getRowAliasNode(rowAlias)
            local aliasNode = rowAliasNodes[rowAlias]
            if aliasNode == nil then
                raw:get(1, rowAlias)
            end
            return aliasNode
        end

        local function getRowOwner(rowIndex)
            local owner = {
                read = function(rowAlias)
                    return raw:read(rowIndex, rowAlias)
                end,
                getAliasSchema = function(rowAlias)
                    return getRowAliasNode(rowAlias)
                end,
                getFieldControlId = function(rowAlias)
                    return getRowFieldControlId(rowIndex, rowAlias)
                end,
            }

            if isWritable then
                owner.write = function(rowAlias, value)
                    return raw:write(rowIndex, rowAlias, value)
                end
                owner.reset = function(rowAlias)
                    return raw:reset(rowIndex, rowAlias)
                end
            end

            return owner
        end

        local function getRowOwnerToken(rowIndex)
            rowIndex = math.floor(tonumber(rowIndex) or 0)
            local token = rowOwnerTokens[rowIndex]
            if not token then
                token = {}
                rowOwnerTokens[rowIndex] = token
            end
            return token
        end

        function handle.count(self)
            requireMethodSelf(countContext, self, handle)
            if isDrawPhase then
                phaseGate.requireOwnerDraw(phaseOwner)
            else
                phaseGate.requireRuntime(phaseOwner)
            end
            return raw:count()
        end

        function handle.read(self, rowIndex, rowAlias)
            requireMethodSelf(readContext, self, handle)
            if isDrawPhase then
                phaseGate.requireOwnerDraw(phaseOwner)
            else
                phaseGate.requireRuntime(phaseOwner)
            end
            return raw:read(rowIndex, rowAlias)
        end

        function handle.get(self, rowIndex, rowAlias)
            requireMethodSelf(getContext, self, handle)
            if isDrawPhase then
                phaseGate.requireOwnerDraw(phaseOwner)
            else
                phaseGate.requireRuntime(phaseOwner)
            end
            local aliasNode = getRowAliasNode(rowAlias)
            if aliasNode == nil then
                return nil
            end

            rowIndex = math.floor(tonumber(rowIndex) or 0)
            local rowCache = rowFields[rowIndex]
            if not rowCache then
                rowCache = {}
                rowFields[rowIndex] = rowCache
            end

            local cached = rowCache[rowAlias]
            if cached then
                return cached
            end

            local rawField = storage.field.createKnown(
                getRowOwner(rowIndex),
                rowAlias,
                aliasNode,
                getContext
            )
            local field = createFieldWrapper(rawField, getContext, getRowOwnerToken(rowIndex))
            rowCache[rowAlias] = field
            return field
        end

        function handle.snapshot(self, rowIndex)
            requireMethodSelf(snapshotContext, self, handle)
            if isDrawPhase then
                phaseGate.requireOwnerDraw(phaseOwner)
            else
                phaseGate.requireRuntime(phaseOwner)
            end
            return raw:snapshot(rowIndex)
        end

        function handle.snapshots(self)
            requireMethodSelf(snapshotsContext, self, handle)
            if isDrawPhase then
                phaseGate.requireOwnerDraw(phaseOwner)
            else
                phaseGate.requireRuntime(phaseOwner)
            end
            return raw:snapshots()
        end

        if isWritable then
            function handle.write(self, rowIndex, rowAlias, value)
                requireMethodSelf(writeContext, self, handle)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                return raw:write(rowIndex, rowAlias, value)
            end

            function handle.reset(self, rowIndex, rowAlias)
                requireMethodSelf(resetContext, self, handle)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                return raw:reset(rowIndex, rowAlias)
            end

            function handle.append(self, rowValues)
                requireMethodSelf(appendContext, self, handle)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                local changed = raw:append(rowValues)
                if changed then
                    clearRowStructureCaches()
                end
                return changed
            end

            function handle.insert(self, rowIndex, rowValues)
                requireMethodSelf(insertContext, self, handle)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                local changed = raw:insert(rowIndex, rowValues)
                if changed then
                    clearRowStructureCaches()
                end
                return changed
            end

            function handle.remove(self, rowIndex)
                requireMethodSelf(removeContext, self, handle)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                local changed = raw:remove(rowIndex)
                if changed then
                    clearRowStructureCaches()
                end
                return changed
            end

            function handle.clear(self)
                requireMethodSelf(clearContext, self, handle)
                if isDrawPhase then
                    phaseGate.requireOwnerDraw(phaseOwner)
                else
                    phaseGate.requireRuntime(phaseOwner)
                end
                local changed = raw:clear()
                if changed then
                    clearRowStructureCaches()
                end
                return changed
            end
        end

        return handle
    end

    return {
        get = function(alias)
            if isDrawPhase then
                phaseGate.requireOwnerDraw(phaseOwner)
            else
                phaseGate.requireRuntime(phaseOwner)
            end

            local cached = refs[alias]
            if cached ~= nil then
                return cached
            end

            local node = getSchema(alias)
            if node == nil then
                return nil
            end

            local ref
            if node.type == "table" and not node._isBitAlias then
                ref = createTable(alias, node)
            else
                ref = createField(alias, node)
            end
            refs[alias] = ref
            return ref
        end,
    }
end

return storageRefAdapter
