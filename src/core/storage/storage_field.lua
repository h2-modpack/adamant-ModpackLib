local deps = ...

local logging = deps.logging

local FIELD_KIND = "AdamantStorageField"
local StorageFieldMethods = {}

local function NormalizeAlias(alias, methodName)
    if type(alias) ~= "string" or alias == "" then
        logging.violate("storage.invalid_field_alias",
            "%s: expected non-empty storage field alias",
            tostring(methodName or "StorageField")
        )
    end
    return alias
end

local function ValidateOwner(owner, methodName)
    if type(owner) ~= "table" or type(owner.read) ~= "function" or type(owner.getAliasSchema) ~= "function" then
        logging.violate("storage.invalid_field_owner",
            "%s: expected storage field owner with read(alias) and getAliasSchema(alias)",
            tostring(methodName or "StorageField")
        )
    end
end

local function GetControlId(owner, alias)
    if type(owner.getFieldControlId) == "function" then
        local id = owner.getFieldControlId(alias)
        if id ~= nil then
            return tostring(id)
        end
    end
    return alias
end

local function CreateField(owner, alias, schema, methodName)
    return setmetatable({
        _kind = FIELD_KIND,
        _owner = owner,
        _alias = alias,
        _schema = schema,
        _source = methodName,
    }, {
        __index = StorageFieldMethods,
    })
end

function StorageFieldMethods:read(...)
    if select("#", ...) ~= 0 then
        logging.violate("storage.invalid_field_args",
            "%s: storage field '%s' does not accept read path arguments",
            tostring(self._source or "StorageField.read"),
            tostring(self._alias)
        )
    end
    return self._owner.read(self._alias)
end

function StorageFieldMethods:readAlias(alias)
    return self._owner.read(NormalizeAlias(alias, self._source or "StorageField.readAlias"))
end

function StorageFieldMethods:write(value)
    if type(self._owner.write) ~= "function" then
        logging.violate("storage.readonly_field",
            "%s: storage field '%s' is read-only",
            tostring(self._source or "StorageField.write"),
            tostring(self._alias)
        )
        return false
    end
    return self._owner.write(self._alias, value)
end

function StorageFieldMethods:writeAlias(alias, value)
    if type(self._owner.write) ~= "function" then
        logging.violate("storage.readonly_field",
            "%s: storage field '%s' is read-only",
            tostring(self._source or "StorageField.writeAlias"),
            tostring(self._alias)
        )
        return false
    end
    return self._owner.write(NormalizeAlias(alias, self._source or "StorageField.writeAlias"), value)
end

function StorageFieldMethods:reset()
    if type(self._owner.reset) ~= "function" then
        logging.violate("storage.readonly_field",
            "%s: storage field '%s' cannot be reset",
            tostring(self._source or "StorageField.reset"),
            tostring(self._alias)
        )
        return false
    end
    return self._owner.reset(self._alias)
end

function StorageFieldMethods:schema()
    return self._schema
end

function StorageFieldMethods:alias()
    return self._alias
end

function StorageFieldMethods:controlId()
    return GetControlId(self._owner, self._alias)
end

local storageField = {}

function storageField.is(value)
    return type(value) == "table" and rawget(value, "_kind") == FIELD_KIND
end

function storageField.create(owner, alias, methodName)
    methodName = methodName or "StorageField"
    ValidateOwner(owner, methodName)
    alias = NormalizeAlias(alias, methodName)

    local schema = owner.getAliasSchema(alias)
    if not schema then
        logging.violate("storage.unknown_field_alias",
            "%s: unknown storage field alias '%s'",
            tostring(methodName),
            tostring(alias)
        )
        return nil
    end

    return CreateField(owner, alias, schema, methodName)
end

function storageField.createKnown(owner, alias, schema, methodName)
    methodName = methodName or "StorageField"
    ValidateOwner(owner, methodName)
    alias = NormalizeAlias(alias, methodName)

    if not schema then
        logging.violate("storage.unknown_field_alias",
            "%s: unknown storage field alias '%s'",
            tostring(methodName),
            tostring(alias)
        )
        return nil
    end

    return CreateField(owner, alias, schema, methodName)
end

return storageField
