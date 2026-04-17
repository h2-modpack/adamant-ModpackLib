local internal = AdamantModpackLib_Internal
local ui = internal.ui
local WidgetFns = public.widgets

local NormalizeColor = ui.NormalizeColor

local function ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and type(imgui.IsItemHovered) == "function" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
end

function WidgetFns.separator(imgui)
    imgui.Separator()
end

function WidgetFns.text(imgui, text, opts)
    opts = opts or {}
    local renderedText = tostring(text or "")
    local color = NormalizeColor(opts.color)
    if opts.alignToFramePadding == true and type(imgui.AlignTextToFramePadding) == "function" then
        imgui.AlignTextToFramePadding()
    end
    if type(color) == "table" then
        imgui.TextColored(color[1], color[2], color[3], color[4], renderedText)
    else
        imgui.Text(renderedText)
    end
    ShowTooltip(imgui, opts.tooltip)
end
