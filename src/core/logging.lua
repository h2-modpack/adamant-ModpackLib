local internal = AdamantModpackLib_Internal
local loggingInternal = internal.logging

public.logging = public.logging or {}
local logging = public.logging
local FormatMessage = loggingInternal.formatMessage

---@alias LogName string

--- Emits a module-scoped warning when the supplied condition is enabled.
---@param packId LogName Module or pack identifier used as the log prefix.
---@param enabled boolean Whether the warning should be emitted.
---@param fmt string Message format string.
function logging.warnIf(packId, enabled, fmt, ...)
    if not enabled then return end
    print(FormatMessage("[" .. packId .. "] ", fmt, ...))
end

--- Emits a module-scoped warning unconditionally.
---@param packId LogName Module or pack identifier used as the log prefix.
---@param fmt string Message format string.
function logging.warn(packId, fmt, ...)
    print(FormatMessage("[" .. packId .. "] ", fmt, ...))
end

--- Emits a module-scoped log line when the supplied condition is enabled.
---@param name LogName Module or subsystem identifier used as the log prefix.
---@param enabled boolean Whether the log line should be emitted.
---@param fmt string Message format string.
function logging.logIf(name, enabled, fmt, ...)
    if not enabled then return end
    print("[" .. name .. "] " .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt))
end
