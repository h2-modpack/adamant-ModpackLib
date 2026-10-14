local helpers = ...
local widgets = {}

function widgets.inputText(imgui, field, opts)
    opts = opts or helpers.EMPTY_OPTS
    local controlId = opts.id ~= nil and tostring(opts.id) or field:controlId()
    local current = tostring(field:read() or "")
    local maxLen = math.max(math.floor(tonumber(opts.maxLen) or 256), 1)

    local pushedWidth = helpers.BeginLabeledControl(imgui, opts, 120)
    local nextValue, changed = imgui.InputText("##" .. tostring(controlId), current, maxLen)
    helpers.EndLabeledControl(imgui, opts, pushedWidth)
    if changed then
        field:write(nextValue)
        helpers.StageAction("draw.widgets.inputText", opts, nextValue)
        return true
    end
    return false
end

return widgets
