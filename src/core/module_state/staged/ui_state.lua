local deps = ...

local logging = deps.logging
local phaseGate = deps.phaseGate
local storage = deps.storage

local uiState = {}

local function requireMethodSelf(context, self, expected)
    if self ~= expected then
        logging.violate("api.invalid_method_call", "%s must be called with ':' method syntax", context)
    end
end

---@class DrawState
---@field get fun(alias: string): StorageField|StorageTableStagedState|nil
---@field read fun(alias: string, ...): any
---@field write fun(alias: string, ...): boolean|nil
---@field resetAll fun(opts: table|nil): boolean, number

--- Narrows full staged state to the module author UI surface.
--- Host internals keep the private commit/reload/snapshot methods.
---@param stagedState StagedState
---@param phaseOwner table
---@return DrawState
function uiState.create(stagedState, phaseOwner)
    local refs = {}
    local fieldOwnerToken = {}

    local fieldOwner = {
        read = function(alias)
            return stagedState.read(alias)
        end,
        write = function(alias, value)
            return stagedState.write(alias, value)
        end,
        reset = function(alias)
            return stagedState.reset(alias)
        end,
        getAliasSchema = function(alias)
            return stagedState.getAliasSchema(alias)
        end,
    }

    local function getSchema(alias)
        local node = type(alias) == "string" and stagedState.getAliasSchema(alias) or nil
        if not node then
            return stagedState.get(alias)
        end
        return node
    end

    local function createFieldWrapper(rawField, source, ownerToken)
        local readContext = source .. ":read"
        local writeContext = source .. ":write"
        local resetContext = source .. ":reset"
        local schemaContext = source .. ":schema"
        local aliasContext = source .. ":alias"
        local controlIdContext = source .. ":controlId"
        local ownerContext = source .. ":owner"
        local field
        field = {
            _kind = rawget(rawField, "_kind"),
            read = function(self, ...)
                requireMethodSelf(readContext, self, field)
                phaseGate.requireOwnerDraw(phaseOwner)
                return rawField:read(...)
            end,
            write = function(self, value)
                requireMethodSelf(writeContext, self, field)
                phaseGate.requireOwnerDraw(phaseOwner)
                return rawField:write(value)
            end,
            reset = function(self)
                requireMethodSelf(resetContext, self, field)
                phaseGate.requireOwnerDraw(phaseOwner)
                return rawField:reset()
            end,
            schema = function(self)
                requireMethodSelf(schemaContext, self, field)
                phaseGate.requireOwnerDraw(phaseOwner)
                return rawField:schema()
            end,
            alias = function(self)
                requireMethodSelf(aliasContext, self, field)
                phaseGate.requireOwnerDraw(phaseOwner)
                return rawField:alias()
            end,
            controlId = function(self)
                requireMethodSelf(controlIdContext, self, field)
                phaseGate.requireOwnerDraw(phaseOwner)
                return rawField:controlId()
            end,
            owner = function(self)
                requireMethodSelf(ownerContext, self, field)
                phaseGate.requireOwnerDraw(phaseOwner)
                return ownerToken
            end,
        }
        return field
    end

    local function createField(alias, node)
        local rawField = storage.field.createKnown(fieldOwner, alias, node, "state.get")
        return createFieldWrapper(rawField, "state.get", fieldOwnerToken)
    end

    local function createTable(alias, node)
        local raw = stagedState.table(alias)
        local rowAliasNodes = storage.getAliases(node.row)
        local rowFields = {}
        local rowControlIds = {}
        local rowOwnerTokens = {}
        local handle = {}

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
            return {
                read = function(rowAlias)
                    return raw:read(rowIndex, rowAlias)
                end,
                write = function(rowAlias, value)
                    return raw:write(rowIndex, rowAlias, value)
                end,
                reset = function(rowAlias)
                    return raw:reset(rowIndex, rowAlias)
                end,
                getAliasSchema = function(rowAlias)
                    return getRowAliasNode(rowAlias)
                end,
                getFieldControlId = function(rowAlias)
                    return getRowFieldControlId(rowIndex, rowAlias)
                end,
            }
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
            requireMethodSelf("state.get(...):count", self, handle)
            phaseGate.requireOwnerDraw(phaseOwner)
            return raw:count()
        end

        function handle.read(self, rowIndex, rowAlias)
            requireMethodSelf("state.get(...):read", self, handle)
            phaseGate.requireOwnerDraw(phaseOwner)
            return raw:read(rowIndex, rowAlias)
        end

        function handle.write(self, rowIndex, rowAlias, value)
            requireMethodSelf("state.get(...):write", self, handle)
            phaseGate.requireOwnerDraw(phaseOwner)
            return raw:write(rowIndex, rowAlias, value)
        end

        function handle.reset(self, rowIndex, rowAlias)
            requireMethodSelf("state.get(...):reset", self, handle)
            phaseGate.requireOwnerDraw(phaseOwner)
            return raw:reset(rowIndex, rowAlias)
        end

        function handle.get(self, rowIndex, rowAlias)
            requireMethodSelf("state.get(...):get", self, handle)
            phaseGate.requireOwnerDraw(phaseOwner)
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
                "state.get(...):get"
            )
            local field = createFieldWrapper(rawField, "state.get(...):get", getRowOwnerToken(rowIndex))
            rowCache[rowAlias] = field
            return field
        end

        function handle.snapshot(self, rowIndex)
            requireMethodSelf("state.get(...):snapshot", self, handle)
            phaseGate.requireOwnerDraw(phaseOwner)
            return raw:snapshot(rowIndex)
        end

        function handle.snapshots(self)
            requireMethodSelf("state.get(...):snapshots", self, handle)
            phaseGate.requireOwnerDraw(phaseOwner)
            return raw:snapshots()
        end

        function handle.append(self, rowValues)
            requireMethodSelf("state.get(...):append", self, handle)
            phaseGate.requireOwnerDraw(phaseOwner)
            local changed = raw:append(rowValues)
            if changed then
                clearRowStructureCaches()
            end
            return changed
        end

        function handle.insert(self, rowIndex, rowValues)
            requireMethodSelf("state.get(...):insert", self, handle)
            phaseGate.requireOwnerDraw(phaseOwner)
            local changed = raw:insert(rowIndex, rowValues)
            if changed then
                clearRowStructureCaches()
            end
            return changed
        end

        function handle.remove(self, rowIndex)
            requireMethodSelf("state.get(...):remove", self, handle)
            phaseGate.requireOwnerDraw(phaseOwner)
            local changed = raw:remove(rowIndex)
            if changed then
                clearRowStructureCaches()
            end
            return changed
        end

        function handle.clear(self)
            requireMethodSelf("state.get(...):clear", self, handle)
            phaseGate.requireOwnerDraw(phaseOwner)
            local changed = raw:clear()
            if changed then
                clearRowStructureCaches()
            end
            return changed
        end

        return handle
    end

    local function getDataObject(alias)
        phaseGate.requireOwnerDraw(phaseOwner)
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
    end

    return {
        get = getDataObject,
        read = function(alias, ...)
            phaseGate.requireOwnerDraw(phaseOwner)
            local ref = stagedState.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
        write = function(alias, ...)
            phaseGate.requireOwnerDraw(phaseOwner)
            local ref = stagedState.get(alias)
            if ref == nil then
                return nil
            end
            return ref:write(...)
        end,
        resetAll = function(opts)
            phaseGate.requireOwnerDraw(phaseOwner)
            return stagedState.resetAll(opts)
        end,
    }
end

return uiState
