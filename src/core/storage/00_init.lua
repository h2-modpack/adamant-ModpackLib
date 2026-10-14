local deps = ...

local logging = deps.logging
local values = deps.values

local typesModule = import('core/storage/types.lua', nil, {
    logging = logging,
})
local StorageTypes = typesModule.types

local nodeOps = import('core/storage/node_ops.lua', nil, {
    values = values,
    types = StorageTypes,
})

local packed = import('core/storage/packed.lua', nil, {
    logging = logging,
    types = StorageTypes,
    IsInteger = typesModule.IsInteger,
    nodeOps = nodeOps,
})

local field = import('core/storage/storage_field.lua', nil, {
    logging = logging,
})

local aliasAccess = import('core/storage/alias_access.lua', nil, {
    nodeOps = nodeOps,
    packed = packed,
})

local tableStorage = import('core/storage/table.lua', nil, {
    logging = logging,
    values = values,
    nodeOps = nodeOps,
    aliasAccess = aliasAccess,
    field = field,
})
-- Closes the types <-> table recursion: table values dispatch row cells back through
-- nodeOps, and nodeOps dispatches table roots to this descriptor.
StorageTypes.table = tableStorage.tableType

local schema = import('core/storage/schema.lua', nil, {
    logging = logging,
    identifiers = deps.identifiers,
    types = StorageTypes,
    NormalizeInteger = typesModule.NormalizeInteger,
    nodeOps = nodeOps,
    packed = packed,
    tableStorage = tableStorage,
})

return {
    validate = schema.validate,
    getRoots = schema.getRoots,
    getPersistRoots = schema.getPersistRoots,
    getStagedRoots = schema.getStagedRoots,
    getAliases = schema.getAliases,
    isPrivateAlias = schema.isPrivateAlias,
    valuesEqual = nodeOps.valuesEqual,
    NormalizeStorageValue = nodeOps.normalize,
    toHash = nodeOps.toHash,
    fromHash = nodeOps.fromHash,
    isHashTokenValid = nodeOps.isHashTokenValid,
    readAlias = aliasAccess.readAlias,
    writeAlias = aliasAccess.writeAlias,
    field = field,
    table = {
        CreateTableHandle = tableStorage.CreateTableHandle,
        ForEachNormalizedTableCell = tableStorage.ForEachNormalizedTableCell,
    },
    packed = {
        DecodePackedChild = packed.DecodePackedChild,
        getPackedAliases = packed.getPackedAliases,
    },
}
