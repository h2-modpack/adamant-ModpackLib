local deps = ...
local libConfig = deps.config
local DefaultViolationPolicy = import 'core/logging/policies.lua'

local logging = {}

local AllowedViolationSeverity = {
    error = true,
    warn = true,
    debug = true,
    ignore = true,
}

local function formatLogMessage(prefix, fmt, ...)
    return prefix .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt)
end

-- Policies are source-owned and never mutated; severities are checked once per import.
for id, policy in pairs(DefaultViolationPolicy) do
    if not AllowedViolationSeverity[policy.severity] then
        error(formatLogMessage("[lib] violation.invalid_severity: ",
            "%s is configured with invalid severity '%s'", id, tostring(policy.severity)), 0)
    end
end

function logging.printWithPrefix(prefix, fmt, ...)
    print(formatLogMessage(prefix, fmt, ...))
end

function logging.printWithPrefixIf(enabled, prefix, fmt, ...)
    if enabled then
        logging.printWithPrefix(prefix, fmt, ...)
    end
end

function logging.isDiagnosticEnabled(subsystem)
    if type(subsystem) ~= "string" or subsystem == "" then
        return false
    end

    local diagnostics = libConfig.Diagnostics
    if diagnostics == true then
        return true
    end
    if type(diagnostics) ~= "table" then
        return false
    end

    local diagnostic = diagnostics[subsystem]
    return diagnostic == true or (type(diagnostic) == "table" and diagnostic.enabled == true)
end

---@param subsystem string
---@param fmt string
function logging.diagnose(subsystem, fmt, ...)
    if not logging.isDiagnosticEnabled(subsystem) then
        return false
    end

    logging.printWithPrefix("[lib-diagnostic:" .. subsystem .. "] ", fmt, ...)
    return true
end

---@param id string Policy id from policies.lua.
---@param fmt string
function logging.violate(id, fmt, ...)
    local policy = DefaultViolationPolicy[id]
    if policy == nil then
        error(formatLogMessage("[lib] violation.unknown_id: ", "unknown violation id '%s'", tostring(id)), 2)
    end
    local severity = policy.severity

    local message = formatLogMessage("[lib] " .. id .. ": ", fmt, ...)
    if severity == "error" then
        if debug and type(debug.traceback) == "function" then
            error(debug.traceback(message, 2), 0)
        end
        error(message, 2)
    elseif severity == "warn" then
        print(message)
    elseif severity == "debug" and libConfig.DebugMode then
        print(message)
    end

    return severity, message
end

return logging
