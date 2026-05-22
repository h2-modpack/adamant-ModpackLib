local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local lifecycle = deps.lifecycle
local author = {}

local function requireHostRecord(host, apiName)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("mutation.invalid_registration", "%s: expected managed module host record", apiName)
    end
    return record
end

local function requireDeclarationOpen(host, apiName)
    local record = requireHostRecord(host, "host.mutation." .. apiName)
    if record.activating == true then
        logging.violate("mutation.invalid_registration", "host.mutation.%s cannot be called during host activation", apiName)
    end
    if record.activated == true then
        logging.violate("mutation.invalid_registration", "host.mutation.%s cannot be called after host activation", apiName)
    end
    return record
end

function author.create(host)
    return {
        patch = function(callback)
            local record = requireDeclarationOpen(host, "patch")
            return lifecycle.declarePatch(record.mutationBundle, callback)
        end,
    }
end

return author
