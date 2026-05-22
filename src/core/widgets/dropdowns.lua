local helpers = ...
local imguiHelpers = helpers.imguiHelpers
local widgets = {}
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
---@return boolean pushedWidth
local function BeginLabeledDropdownControl(imgui, opts)
    local labelText = tostring(opts.label or "")
    local controlWidth = tonumber(opts.controlWidth) or 0

    if labelText ~= "" then
        helpers.DrawInlineLabel(imgui, labelText, opts.tooltip, opts.labelWidth, opts.controlGap)
    end

    if controlWidth > 0 then
        imgui.PushItemWidth(controlWidth)
    end
    return controlWidth > 0
end

---@param imgui table
---@param opts DropdownOpts|PackedDropdownOpts
---@param pushedWidth boolean
local function EndLabeledDropdownControl(imgui, opts, pushedWidth)
    if pushedWidth then
        imgui.PopItemWidth()
    end
    helpers.ShowTooltip(imgui, opts.tooltip)
end

local function GetDropdownPreview(opts, values, current, valueColors)
    local previewText = ""
    local previewColor = nil
    for _, value in ipairs(values) do
        local label = helpers.ChoiceDisplay(opts, value)
        local color = valueColors and valueColors[value] or nil
        if previewText == "" then
            previewText = label
            previewColor = color
        end
        if value == current then
            return label, color
        end
    end
    return previewText, previewColor
end

---@param imgui table
---@param field StorageField
---@param opts DropdownOpts|nil
---@return boolean
function widgets.dropdown(imgui, field, opts)
    opts = opts or helpers.EMPTY_OPTS
    local controlId = opts.id or field:controlId()
    local current = helpers.NormalizeChoiceValue(opts, field:read())
    local values = opts.values or helpers.EMPTY_LIST
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local previewText, previewColor = GetDropdownPreview(opts, values, current, valueColors)
    local pushedWidth = BeginLabeledDropdownControl(imgui, opts)
    local opened = imgui.BeginCombo(
        "##" .. tostring(controlId),
        previewColor and "" or previewText,
        COMBO_FLAG_NONE
    )
    if previewColor then
        DrawComboPreviewText(imgui, previewText, previewColor)
    end
    local changed = false
    if opened then
        for index, value in ipairs(values) do
            local label = helpers.ChoiceDisplay(opts, value)
            local color = valueColors and valueColors[value] or nil
            local clicked = helpers.SelectableWithValueColor(
                imgui,
                helpers.MakeSelectableId(label, index),
                value == current,
                color
            )
            if clicked and value ~= current then
                field:write(value)
                current = value
                helpers.StageAction("draw.widgets.dropdown", opts, value)
                changed = true
            end
        end
        imgui.EndCombo()
    end
    EndLabeledDropdownControl(imgui, opts, pushedWidth)
    return changed
end

---@param imgui table
---@param field StorageField
---@param opts PackedDropdownOpts|nil
---@return boolean
function widgets.packedDropdown(imgui, field, opts)
    opts = opts or helpers.EMPTY_OPTS
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

    local pushedWidth = BeginLabeledDropdownControl(imgui, opts)
    local opened = imgui.BeginCombo(
        "##" .. tostring(controlId),
        "",
        COMBO_FLAG_NONE
    )
    DrawComboPreviewText(imgui, preview, previewColor)
    local changed = false
    if opened then
        local selectedChild = selection.selectedChild
        if imgui.Selectable(
            helpers.MakeSelectableId(tostring(opts.noneLabel or "None"), "none"),
            selection.state == "none"
        ) then
            local cleared = helpers.ClearPackedChoiceSelection(field, children, selection)
            if cleared then
                helpers.StageAction("draw.widgets.packedDropdown", opts, false)
            end
            changed = cleared or changed
            selectedChild = nil
        end
        for _, child in ipairs(children) do
            local childLabel = helpers.GetPackedChoiceLabel(opts, child)
            local childColor = valueColors and valueColors[child.alias] or nil
            local clicked = helpers.SelectableWithValueColor(
                imgui,
                helpers.MakeSelectableId(childLabel, child.alias),
                selectedChild ~= nil and selectedChild.alias == child.alias,
                childColor
            )
            if clicked then
                local selected = helpers.ApplyPackedChoiceSelection(field, children, child.alias, selection)
                if selected then
                    helpers.StageAction("draw.widgets.packedDropdown", opts, child.alias)
                end
                changed = selected or changed
                selectedChild = child
            end
        end
        imgui.EndCombo()
    end
    EndLabeledDropdownControl(imgui, opts, pushedWidth)
    return changed
end

---@param field StorageField
---@param opts PackedDropdownOpts|PackedRadioOpts|nil
---@return string|nil selectedAlias
function widgets.getPackedChoiceAlias(field, opts)
    opts = opts or helpers.EMPTY_OPTS
    local children = helpers.ResolvePackedChildren(field)
    local selection = helpers.ClassifyPackedChoice(opts, field, children)
    return selection.selectedChild and selection.selectedChild.alias or nil
end

return widgets
