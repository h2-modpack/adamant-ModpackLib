local helpers = ...
local widgets = {}

---@class InputTextOpts
---@field label string|nil
---@field tooltip string|nil
---@field maxLen number|nil
---@field labelWidth number|nil
---@field controlWidth number|nil
---@field controlGap number|nil
---@field action DrawActionRef|nil
---@field value any

---@param imgui table
---@param field StorageField
---@param opts InputTextOpts|nil
---@return boolean
function widgets.inputText(imgui, field, opts)
    opts = opts or helpers.EMPTY_OPTS
    local fieldControlId = field:controlId()
    local current = tostring(field:read() or "")
    local maxLen = math.max(math.floor(tonumber(opts.maxLen) or 256), 1)
    local label = tostring(opts.label or "")
    local controlWidth = tonumber(opts.controlWidth) or 120

    if label ~= "" then
        helpers.DrawInlineLabel(imgui, label, opts.tooltip, opts.labelWidth, opts.controlGap)
    end

    if controlWidth > 0 then
        imgui.PushItemWidth(controlWidth)
    end
    local nextValue, changed = imgui.InputText("##" .. tostring(fieldControlId), current, maxLen)
    if controlWidth > 0 then
        imgui.PopItemWidth()
    end
    helpers.ShowTooltip(imgui, opts.tooltip)
    if changed then
        field:write(nextValue)
        helpers.StageAction("draw.widgets.inputText", opts, nextValue)
        return true
    end
    return false
end

return widgets
