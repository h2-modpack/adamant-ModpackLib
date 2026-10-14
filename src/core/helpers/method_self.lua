local deps = ...

local logging = deps.logging

---Rejects author handle-method calls made with `.` instead of `:` syntax.
---@param context string
---@param self any
---@param expected table
local function requireMethodSelf(context, self, expected)
    if self ~= expected then
        logging.violate("api.invalid_method_call", "%s must be called with ':' method syntax", context)
    end
end

return requireMethodSelf
