local deps = ...

local logging = deps.logging
local moduleRegistry = deps.moduleRegistry
local registrations = deps.registrations
local data = deps.data
local moduleAdapter = {}

local function requireModuleRecord(module, context)
    local record = moduleRegistry.getRecord(module)
    if not record then
        logging.violate("shared.invalid_args", "%s: expected managed module record", context)
    end
    return record
end

function moduleAdapter.installForModule(module)
    local record = requireModuleRecord(module, "shared.installForModule")
    local ownerId = module.getOwnerId()
    local dataReceipt = data.install(ownerId, record.sharedDataDeclarations)
    local eventReceipt = registrations.install(ownerId, record.sharedEventRegistrations)
    local committedData = false
    local committedEvents = false

    local function release(methodName)
        local ok, err = true, nil
        if committedEvents then
            ok, err = eventReceipt[methodName]()
            committedEvents = false
        end
        if committedData then
            local dataOk, dataErr = dataReceipt[methodName]()
            committedData = false
            if ok and not dataOk then
                ok, err = dataOk, dataErr
            end
        end
        return ok, err
    end

    return {
        commit = function()
            local ok, err = dataReceipt.commit()
            if not ok then
                return false, err
            end
            committedData = true

            ok, err = eventReceipt.commit()
            if not ok then
                dataReceipt.dispose()
                committedData = false
                return false, err
            end
            committedEvents = true
            return true, nil
        end,
        dispose = function()
            return release("dispose")
        end,
        retire = function()
            return release("retire")
        end,
    }
end

return moduleAdapter
