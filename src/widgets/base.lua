local internal = AdamantModpackLib_Internal
local WidgetFns = public.widgets

local widgetHelpers = internal.widgetHelpers
local NormalizeColor = widgetHelpers.NormalizeColor

---@class TextOpts
---@field color Color|nil
---@field tooltip string|nil
---@field alignToFramePadding boolean|nil

local function ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
end

---@param imgui table
---@return nil
function WidgetFns.separator(imgui)
    imgui.Separator()
end

---@param imgui table
---@param text any
---@param opts TextOpts|nil
---@return nil
function WidgetFns.text(imgui, text, opts)
    opts = opts or {}
    local renderedText = tostring(text or "")
    local color = NormalizeColor(opts.color)
    if opts.alignToFramePadding == true then
        imgui.AlignTextToFramePadding()
    end
    if type(color) == "table" then
        imgui.TextColored(color[1], color[2], color[3], color[4], renderedText)
    else
        imgui.Text(renderedText)
    end
    ShowTooltip(imgui, opts.tooltip)
end
