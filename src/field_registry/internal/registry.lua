local internal = AdamantModpackLib_Internal
local registry = internal.registry

function registry.validateRegistries()
    local storageTypes = public.registry.storage

    for typeName, item in pairs(storageTypes) do
        if type(item) ~= "table" then
            error(("Storage type '%s' must be a table"):format(tostring(typeName)), 0)
        end
        for _, method in ipairs({ "validate", "normalize", "toHash", "fromHash" }) do
            if type(item[method]) ~= "function" then
                error(("Storage type '%s' is missing required method '%s'"):format(
                tostring(typeName), method), 0)
            end
        end
    end
    return true
end
