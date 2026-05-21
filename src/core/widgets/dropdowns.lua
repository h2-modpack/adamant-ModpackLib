local helpers = ...
local imguiHelpers = helpers.imguiHelpers
---@class DropdownOpts
---@field id string|number|nil
---@field label string|nil
---@field tooltip string|nil
---@field values ChoiceValue[]|nil
---@field default ChoiceValue|nil
---@field displayValues ChoiceDisplayValues|nil
---@field valueColors ValueColorMap|nil
---@field labelWidth number|nil
---@field controlWidth number|nil
---@field controlGap number|nil
---@field action DrawActionRef|nil
---@field value any

---@class PackedDropdownOpts
---@field id string|number|nil
---@field label string|nil
---@field tooltip string|nil
---@field labelWidth number|nil
---@field controlWidth number|nil
---@field controlGap number|nil
---@field displayValues ChoiceDisplayValues|nil
---@field valueColors table<string, Color>|nil
---@field noneLabel string|nil
---@field multipleLabel string|nil
---@field selectionMode PackedSelectionMode|nil
---@field action DrawActionRef|nil
---@field value any

local COMBO_FLAG_NONE = imguiHelpers.ImGuiComboFlags.None
local IMGUI_COL_TEXT = imguiHelpers.ImGuiCol.Text

local function DrawComboPreviewText(imgui, previewText, previewColor)
    local drawList = imgui.GetWindowDrawList()
    if drawList == nil then
        return
    end

    local style = imgui.GetStyle()
    local rectMinX, rectMinY = imgui.GetItemRectMin()
    local rectMaxX, rectMaxY = imgui.GetItemRectMax()
    local _, textHeight = imgui.CalcTextSize(previewText)
    local framePaddingX = style.FramePadding.x
    local itemInnerSpacingX = style.ItemInnerSpacing.x
    local arrowWidth = imgui.GetFrameHeight()
    local textMinX = rectMinX + framePaddingX
    local textMaxX = rectMaxX - arrowWidth - itemInnerSpacingX
    local textPosY = rectMinY + math.max(((rectMaxY - rectMinY) - textHeight) * 0.5, 0)
    local colorU32

    if textMaxX <= textMinX then
        return
    end

    if type(previewColor) == "table" then
        colorU32 = imgui.GetColorU32(previewColor[1], previewColor[2], previewColor[3], previewColor[4] or 1)
    else
        colorU32 = imgui.GetColorU32(IMGUI_COL_TEXT, 1)
    end

    imgui.PushClipRect(textMinX, rectMinY, textMaxX, rectMaxY, true)
    imgui.ImDrawListAddText(drawList, textMinX, textPosY, colorU32, previewText)
    imgui.PopClipRect()
end

---@param imgui table
---@param opts DropdownOpts|PackedDropdownOpts
---@param previewColor Color|nil
---@param drawControl fun(controlWidth: number|nil, previewColor: Color|nil): boolean
---@return boolean
local function DrawLabeledDropdownControl(imgui, opts, previewColor, drawControl)
    local labelText = tostring(opts.label or "")
    local controlWidth = tonumber(opts.controlWidth) or 0

    if labelText ~= "" then
        helpers.DrawInlineLabel(imgui, labelText, opts.tooltip, opts.labelWidth, opts.controlGap)
    end

    if controlWidth > 0 then
        imgui.PushItemWidth(controlWidth)
    end
    local changed = drawControl(controlWidth, previewColor) == true
    if controlWidth > 0 then
        imgui.PopItemWidth()
    end
    helpers.ShowTooltip(imgui, opts.tooltip)
    return changed
end

---@param imgui table
---@param field StorageField
---@param opts DropdownOpts|nil
---@return boolean
function helpers.widgets.dropdown(imgui, field, opts)
    opts = opts or {}
    local controlId = opts.id or field:controlId()
    local current = helpers.NormalizeChoiceValue(opts, field:read())
    local optionEntries = {}
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    for index, value in ipairs(opts.values or {}) do
        optionEntries[#optionEntries + 1] = {
            value = value,
            label = helpers.ChoiceDisplay(opts, value),
            color = valueColors and valueColors[value] or nil,
            uniqueId = index,
        }
    end

    local currentOption = optionEntries[1]
    for _, option in ipairs(optionEntries) do
        if option.value == current then
            currentOption = option
            break
        end
    end
    local previewText = currentOption and currentOption.label or ""
    local previewColor = currentOption and currentOption.color or nil

    return DrawLabeledDropdownControl(imgui, opts, nil, function()
        local opened = imgui.BeginCombo(
            "##" .. tostring(controlId),
            previewColor and "" or previewText,
            COMBO_FLAG_NONE
        )
        if previewColor then
            DrawComboPreviewText(imgui, previewText, previewColor)
        end
        if not opened then
            return false
        end
        local changed = false
        for _, option in ipairs(optionEntries) do
            local clicked = helpers.DrawWithValueColor(imgui, option.color, function()
                return imgui.Selectable(helpers.MakeSelectableId(option.label, option.uniqueId), option.value == current)
            end)
            if clicked and option.value ~= current then
                field:write(option.value)
                current = option.value
                helpers.StageAction("draw.widgets.dropdown", opts, option.value)
                changed = true
            end
        end
        imgui.EndCombo()
        return changed
    end)
end

---@param imgui table
---@param field StorageField
---@param opts PackedDropdownOpts|nil
---@return boolean
function helpers.widgets.packedDropdown(imgui, field, opts)
    opts = opts or {}
    local controlId = opts.id or field:controlId()
    local children = helpers.ResolvePackedChildren(field)
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local selection = helpers.ClassifyPackedChoice(opts, field, children)
    local preview = tostring(opts.noneLabel or "None")
    local previewColor = nil
    if selection.state == "single" and selection.selectedChild then
        preview = helpers.GetPackedChoiceLabel(opts, selection.selectedChild)
        previewColor = valueColors and valueColors[selection.selectedChild.alias] or nil
    elseif selection.state == "multiple" then
        preview = tostring(opts.multipleLabel or "Multiple")
    end

    return DrawLabeledDropdownControl(imgui, opts, nil, function()
        local opened = imgui.BeginCombo(
            "##" .. tostring(controlId),
            "",
            COMBO_FLAG_NONE
        )
        DrawComboPreviewText(imgui, preview, previewColor)
        if not opened then
            return false
        end
        local changed = false
        local currentSelection = selection
        if imgui.Selectable(
            helpers.MakeSelectableId(tostring(opts.noneLabel or "None"), "none"),
            currentSelection.state == "none"
        ) then
            local cleared = helpers.ClearPackedChoiceSelection(field, children, currentSelection)
            if cleared then
                helpers.StageAction("draw.widgets.packedDropdown", opts, false)
            end
            changed = cleared or changed
            currentSelection = {
                state = "none",
                selectedChild = nil,
                mode = currentSelection.mode,
                noneValue = currentSelection.noneValue,
            }
        end
        for _, child in ipairs(children) do
            local childLabel = helpers.GetPackedChoiceLabel(opts, child)
            local childColor = valueColors and valueColors[child.alias] or nil
            local clicked = helpers.DrawWithValueColor(imgui, childColor, function()
                local isSelected = currentSelection.selectedChild ~= nil
                    and currentSelection.selectedChild.alias == child.alias
                return imgui.Selectable(helpers.MakeSelectableId(childLabel, child.alias), isSelected)
            end)
            if clicked then
                local selected = helpers.ApplyPackedChoiceSelection(field, children, child.alias, currentSelection)
                if selected then
                    helpers.StageAction("draw.widgets.packedDropdown", opts, child.alias)
                end
                changed = selected or changed
                currentSelection = {
                    state = "single",
                    selectedChild = child,
                    mode = currentSelection.mode,
                    noneValue = currentSelection.noneValue,
                }
            end
        end
        imgui.EndCombo()
        return changed
    end)
end

---@param field StorageField
---@param opts PackedDropdownOpts|PackedRadioOpts|nil
---@return string|nil selectedAlias
function helpers.widgets.getPackedChoiceAlias(field, opts)
    opts = opts or {}
    local children = helpers.ResolvePackedChildren(field)
    local selection = helpers.ClassifyPackedChoice(opts, field, children)
    return selection.selectedChild and selection.selectedChild.alias or nil
end
