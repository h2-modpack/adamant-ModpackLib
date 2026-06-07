local helpers = ...
local widgets = {}

function widgets.separator(imgui)
    imgui.Separator()
end

function widgets.text(imgui, text, opts)
    opts = opts or helpers.EMPTY_OPTS
    local renderedText = tostring(text or "")
    if opts.alignToFramePadding == true then
        imgui.AlignTextToFramePadding()
    end
    if not helpers.TextWithValueColor(imgui, opts.color, renderedText) then
        imgui.Text(renderedText)
    end
    helpers.ShowTooltip(imgui, opts.tooltip)
end

return widgets
