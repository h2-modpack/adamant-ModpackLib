local helpers = ...
local widgets = {}

local DEFAULT_CONTROL_WIDTH = 220

local function NormalizeSliderValue(value, defaultValue, minValue, maxValue)
    local num = tonumber(value)
    if num == nil then
        num = tonumber(defaultValue) or minValue
    end
    num = math.floor(num)
    if num < minValue then num = minValue end
    if num > maxValue then num = maxValue end
    return num
end

--- Integer slider bound to one storage field. Writes while dragging, so the staged value follows the
--- handle; the optional action is staged on every change.
function widgets.slider(imgui, field, opts)
    opts = opts or helpers.EMPTY_OPTS
    local id = opts.id ~= nil and tostring(opts.id) or field:controlId()
    local minValue = math.floor(tonumber(opts.min) or 0)
    local maxValue = math.floor(tonumber(opts.max) or 100)
    local current = NormalizeSliderValue(field:read(), opts.default, minValue, maxValue)

    local pushedWidth = helpers.BeginLabeledControl(imgui, opts, DEFAULT_CONTROL_WIDTH)
    local nextValue, used = imgui.SliderInt("##" .. id, current, minValue, maxValue)
    helpers.EndLabeledControl(imgui, opts, pushedWidth)

    if not used then
        return false
    end
    local normalized = NormalizeSliderValue(nextValue, opts.default, minValue, maxValue)
    if normalized == current then
        return false
    end
    field:write(normalized)
    helpers.StageAction("draw.widgets.slider", opts, normalized)
    return true
end

return widgets
