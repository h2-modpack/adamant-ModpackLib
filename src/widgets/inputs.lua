local internal = AdamantModpackLib_Internal
local WidgetFns = public.widgets

---@class InputTextOpts
---@field label string|nil
---@field tooltip string|nil
---@field maxLen number|nil
---@field controlWidth number|nil
---@field controlGap number|nil

local function ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
end

---@param imgui table
---@param uiState UiState
---@param alias string
---@param opts InputTextOpts|nil
---@return boolean
function WidgetFns.inputText(imgui, uiState, alias, opts)
    opts = opts or {}
    local current = tostring((uiState and uiState.view and uiState.view[alias]) or "")
    local maxLen = math.max(math.floor(tonumber(opts.maxLen) or 256), 1)
    local label = tostring(opts.label or "")
    local controlWidth = tonumber(opts.controlWidth) or 120
    local controlGap = tonumber(opts.controlGap)
    if controlGap == nil or controlGap < 0 then
        controlGap = imgui.GetStyle().ItemSpacing.x
    end

    if label ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(label)
        ShowTooltip(imgui, opts.tooltip)
        imgui.SameLine()
        if controlGap > 0 then
            imgui.SetCursorPosX(imgui.GetCursorPosX() + controlGap)
        end
    end

    if controlWidth > 0 then
        imgui.PushItemWidth(controlWidth)
    end
    local nextValue, changed = imgui.InputText("##" .. tostring(alias), current, maxLen)
    if controlWidth > 0 then
        imgui.PopItemWidth()
    end
    ShowTooltip(imgui, opts.tooltip)
    if changed then
        uiState.set(alias, nextValue)
        return true
    end
    return false
end
