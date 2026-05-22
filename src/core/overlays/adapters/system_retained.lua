local deps = ...

local logging = deps.logging
local retained = deps.retained
local overlayOrder = deps.order
local systemAdapter = {}

local function define(ownerId, register)
    if type(register) ~= "function" then
        logging.violate("overlays.invalid_registration", "system.overlays.define: register must be a function")
    end

    retained.refresh(ownerId, ownerId, nil, nil, register, { system = true })
    retained.dispatchCommit(ownerId, {})
    return true
end

function systemAdapter.create(_, ownerId)
    return {
        order = overlayOrder,
        define = function(register)
            return define(ownerId, register)
        end,
    }
end

return systemAdapter
