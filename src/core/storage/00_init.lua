local deps = ...

local logging = deps.logging
local values = deps.values
local storage = {}

local typesModule = import('core/storage/types.lua', nil, {
    logging = logging,
    storage = storage,
    values = values,
})
storage.types = typesModule.types
storage.NormalizeInteger = typesModule.NormalizeInteger

local packed = import('core/storage/packed.lua', nil, {
    logging = logging,
    storage = storage,
    types = storage.types,
})
storage.packed = packed

storage.field = import('core/storage/storage_field.lua', nil, {
    logging = logging,
})

local tableStorage = import('core/storage/table.lua', nil, {
    logging = logging,
    storage = storage,
    types = storage.types,
    values = values,
})
storage.table = tableStorage

local schema = import('core/storage/schema.lua', nil, {
    logging = logging,
    storage = storage,
    values = values,
    packed = packed,
    tableStorage = tableStorage,
})
storage.validate = schema.validate
storage.getRoots = schema.getRoots
storage.getPersistRoots = schema.getPersistRoots
storage.getStagedRoots = schema.getStagedRoots
storage.getAliases = schema.getAliases
storage.valuesEqual = schema.valuesEqual
storage.NormalizeStorageValue = schema.NormalizeStorageValue
storage.isHashTokenValid = schema.isHashTokenValid

local aliasAccess = import('core/storage/alias_access.lua', nil, {
    storage = storage,
    packed = packed,
})
storage.readAlias = aliasAccess.readAlias
storage.writeAlias = aliasAccess.writeAlias

return storage
