local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local registrations = deps.registrations
local data = deps.data
local hostAdapter = {}

local function requireHostRecord(host, context)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("shared.invalid_args", "%s: expected managed module host record", context)
    end
    return record
end

function hostAdapter.installForHost(host)
    local record = requireHostRecord(host, "shared.installForHost")
    local ownerId = host.getHostId()
    local dataReceipt = data.install(ownerId, record.sharedDataDeclarations)
    local eventReceipt = registrations.install(ownerId, record.sharedEventRegistrations)
    local committedData = false
    local committedEvents = false

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
            local ok, err = true, nil
            if committedEvents then
                ok, err = eventReceipt.dispose()
                committedEvents = false
            end
            if committedData then
                local dataOk, dataErr = dataReceipt.dispose()
                committedData = false
                if ok and not dataOk then
                    ok, err = dataOk, dataErr
                end
            end
            return ok, err
        end,
    }
end

return hostAdapter
