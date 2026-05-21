local helpers = ...

---@class TextOpts
---@field color Color|nil
---@field tooltip string|nil
---@field alignToFramePadding boolean|nil

---@param imgui table
---@return nil
function helpers.widgets.separator(imgui)
    imgui.Separator()
end

---@param imgui table
---@param text any
---@param opts TextOpts|nil
---@return nil
function helpers.widgets.text(imgui, text, opts)
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
