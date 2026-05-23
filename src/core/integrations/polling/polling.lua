local deps = ...

local logging = deps.logging
local registry = deps.registry
local polling = {}

local function validateIntegrationId(context, id)
    if type(id) ~= "string" or id == "" then
        logging.violate("integrations.invalid_args", "%s: id must be a non-empty string", context)
    end
end

local function validateMethodName(context, methodName)
    if type(methodName) ~= "string" or methodName == "" then
        logging.violate("integrations.invalid_args", "%s: methodName must be a non-empty string", context)
    end
end

function polling.poll(context, id, methodName, fallback, ...)
    validateIntegrationId(context, id)
    validateMethodName(context, methodName)

    local provider, providerId = registry.getPreferredProvider(id, function(candidate)
        return candidate.isEnabled == nil or candidate.isEnabled() ~= false
    end)
    local method = provider and provider.methods and provider.methods[methodName] or nil
    if type(method) ~= "table" or type(method.handler) ~= "function" or not method.scope then
        return fallback, providerId
    end

    local ok, result = pcall(method.scope.call, method.handler, ...)
    if not ok then
        logging.violate(
            "integrations.provider_failed",
            "%s.%s provider '%s' failed: %s",
            tostring(id),
            tostring(methodName),
            tostring(providerId),
            tostring(result))
        return fallback, providerId
    end

    return result, providerId
end

return polling
