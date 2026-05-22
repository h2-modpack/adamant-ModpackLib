local deps = ...

local logging = deps.logging
local phaseGate = deps.phaseGate
local storage = deps.storage

local store = {}

local function requireMethodSelf(context, self, expected)
    if self ~= expected then
        logging.violate("api.invalid_method_call", "%s must be called with ':' method syntax", context)
    end
end

---@param persistentState PersistentState
---@param phaseOwner table
---@return Store
function store.create(persistentState, phaseOwner)
    local refs = {}
    local fieldOwnerToken = {}

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
                phaseGate.requireRuntime(phaseOwner)
                return rawField:read(...)
            end,
            write = function(self, value)
                requireMethodSelf(writeContext, self, field)
                phaseGate.requireRuntime(phaseOwner)
                return rawField:write(value)
            end,
            reset = function(self)
                requireMethodSelf(resetContext, self, field)
                phaseGate.requireRuntime(phaseOwner)
                return rawField:reset()
            end,
            schema = function(self)
                requireMethodSelf(schemaContext, self, field)
                phaseGate.requireRuntime(phaseOwner)
                return rawField:schema()
            end,
            alias = function(self)
                requireMethodSelf(aliasContext, self, field)
                phaseGate.requireRuntime(phaseOwner)
                return rawField:alias()
            end,
            controlId = function(self)
                requireMethodSelf(controlIdContext, self, field)
                phaseGate.requireRuntime(phaseOwner)
                return rawField:controlId()
            end,
            owner = function(self)
                requireMethodSelf(ownerContext, self, field)
                phaseGate.requireRuntime(phaseOwner)
                return ownerToken
            end,
        }
        return field
    end

    local function createField(alias)
        return createFieldWrapper(persistentState.get(alias), "store.get", fieldOwnerToken)
    end

    local function createTable(alias)
        local raw = persistentState.table(alias)
        local node = persistentState.getAliasSchema(alias)
        local rowAliasNodes = storage.getAliases(node.row)
        local rowFields = {}
        local rowControlIds = {}
        local rowOwnerTokens = {}
        local handle = {}

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
            requireMethodSelf("store.get(...):count", self, handle)
            phaseGate.requireRuntime(phaseOwner)
            return raw:count()
        end

        function handle.read(self, rowIndex, rowAlias)
            requireMethodSelf("store.get(...):read", self, handle)
            phaseGate.requireRuntime(phaseOwner)
            return raw:read(rowIndex, rowAlias)
        end

        function handle.get(self, rowIndex, rowAlias)
            requireMethodSelf("store.get(...):get", self, handle)
            phaseGate.requireRuntime(phaseOwner)
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
                "store.get(...):get"
            )
            local field = createFieldWrapper(rawField, "store.get(...):get", getRowOwnerToken(rowIndex))
            rowCache[rowAlias] = field
            return field
        end

        function handle.snapshot(self, rowIndex)
            requireMethodSelf("store.get(...):snapshot", self, handle)
            phaseGate.requireRuntime(phaseOwner)
            return raw:snapshot(rowIndex)
        end

        function handle.snapshots(self)
            requireMethodSelf("store.get(...):snapshots", self, handle)
            phaseGate.requireRuntime(phaseOwner)
            return raw:snapshots()
        end

        return handle
    end

    local function getDataObject(alias)
        phaseGate.requireRuntime(phaseOwner)
        local cached = refs[alias]
        if cached ~= nil then
            return cached
        end

        local node = type(alias) == "string" and persistentState.getAliasSchema(alias) or nil
        if node == nil then
            return persistentState.get(alias)
        end

        local ref
        if node.type == "table" and not node._isBitAlias then
            ref = createTable(alias)
        else
            ref = createField(alias)
        end
        refs[alias] = ref
        return ref
    end

    return {
        get = getDataObject,
        read = function(alias, ...)
            phaseGate.requireRuntime(phaseOwner)
            local ref = persistentState.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
    }
end

return store
