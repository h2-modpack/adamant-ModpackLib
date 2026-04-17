local internal = AdamantModpackLib_Internal
local ui = internal.ui
local WidgetFns = public.widgets

local GetStyleMetricX = ui.GetStyleMetricX

local function ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and type(imgui.IsItemHovered) == "function" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
end

function WidgetFns.inputText(imgui, uiState, alias, opts)
    opts = opts or {}
    local current = tostring((uiState and uiState.view and uiState.view[alias]) or "")
    local maxLen = math.max(math.floor(tonumber(opts.maxLen) or 256), 1)
    local label = tostring(opts.label or "")
    local controlWidth = tonumber(opts.controlWidth) or 120
    local controlGap = tonumber(opts.controlGap)
    if controlGap == nil or controlGap < 0 then
        controlGap = GetStyleMetricX(imgui.GetStyle(), "ItemSpacing", 8)
    end

    if label ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(label)
        ShowTooltip(imgui, opts.tooltip)
        imgui.SameLine()
        if controlGap > 0 then
            imgui.SetCursorPosX(ui.GetCursorPosXSafe(imgui) + controlGap)
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
