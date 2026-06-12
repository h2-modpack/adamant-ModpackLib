local deps = ...
local libConfig = deps.config
local DefaultViolationPolicy = import 'core/logging/policies.lua'

local logging = {}
local violationPolicy = {}

local AllowedViolationSeverity = {
    error = true,
    warn = true,
    debug = true,
    ignore = true,
}

function logging.formatLogMessage(prefix, fmt, ...)
    return prefix .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt)
end

function logging.printWithPrefix(prefix, fmt, ...)
    print(logging.formatLogMessage(prefix, fmt, ...))
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

function logging.diagnose(subsystem, fmt, ...)
    assert(type(subsystem) == "string" and subsystem ~= "",
        "logging.diagnose: subsystem must be a non-empty string")
    assert(type(fmt) == "string", "logging.diagnose: fmt must be a string")

    if not logging.isDiagnosticEnabled(subsystem) then
        return false
    end

    logging.printWithPrefix("[lib-diagnostic:" .. subsystem .. "] ", fmt, ...)
    return true
end

for id, entry in pairs(DefaultViolationPolicy) do
    violationPolicy[id] = {
        severity = entry.severity,
        description = entry.description,
    }
end

function logging.violate(id, fmt, ...)
    assert(type(id) == "string" and id ~= "", "logging.violate: id must be a non-empty string")
    assert(type(fmt) == "string", "logging.violate: fmt must be a string")

    local policy = violationPolicy[id]
    if type(policy) ~= "table" then
        error(logging.formatLogMessage("[lib] violation.unknown_id: ", "unknown violation id '%s'", id), 2)
    end
    local severity = policy.severity
    if not AllowedViolationSeverity[severity] then
        error(logging.formatLogMessage("[lib] violation.invalid_severity: ",
            "%s is configured with invalid severity '%s'", id, tostring(severity)), 2)
    end

    local message = logging.formatLogMessage("[lib] " .. id .. ": ", fmt, ...)
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
