local helpers = ...
local imguiHelpers = helpers.imguiHelpers
local widgets = {}

local COMBO_FLAG_NONE = imguiHelpers.ImGuiComboFlags.None
local IMGUI_COL_TEXT = imguiHelpers.ImGuiCol.Text
local RANGE_CACHE_BY_OPTS = setmetatable({}, { __mode = "k" })

local function NormalizeInteger(value, fallback)
    local number = tonumber(value)
    if number == nil then
        return fallback
    end
    return math.floor(number)
end

local function AddRangeValue(values, displayValues, seen, value, prefix, suffix)
    local normalized = NormalizeInteger(value)
    if normalized == nil or seen[normalized] then
        return
    end
    seen[normalized] = true
    values[#values + 1] = normalized
    displayValues[normalized] = prefix .. tostring(normalized) .. suffix
end

local function AddRangeList(values, displayValues, seen, source, prefix, suffix)
    if type(source) ~= "table" then
        AddRangeValue(values, displayValues, seen, source, prefix, suffix)
        return
    end
    for _, value in ipairs(source) do
        AddRangeValue(values, displayValues, seen, value, prefix, suffix)
    end
end

local function BuildRangeChoices(range)
    local minValue = NormalizeInteger(range.min, 0)
    local maxValue = NormalizeInteger(range.max, minValue)
    local step = math.max(NormalizeInteger(range.step, 1), 1)
    local prefix = tostring(range.prefix or "")
    local suffix = tostring(range.suffix or "")
    local values = {}
    local displayValues = {}
    local seen = {}

    AddRangeList(values, displayValues, seen, range.prepend, prefix, suffix)
    for value = minValue, maxValue, step do
        AddRangeValue(values, displayValues, seen, value, prefix, suffix)
    end
    AddRangeList(values, displayValues, seen, range.append, prefix, suffix)

    return values, displayValues
end

local function ResolveDropdownChoices(opts)
    if type(opts.values) == "table" then
        return opts.values, nil
    end

    local range = opts.valueRange
    if type(range) ~= "table" then
        return helpers.EMPTY_LIST, nil
    end

    local cached = RANGE_CACHE_BY_OPTS[opts]
    if cached ~= nil
        and cached.range == range
        and cached.min == range.min
        and cached.max == range.max
        and cached.step == range.step
        and cached.prepend == range.prepend
        and cached.append == range.append
        and cached.prefix == range.prefix
        and cached.suffix == range.suffix then
        return cached.values, cached.displayValues
    end

    local values, displayValues = BuildRangeChoices(range)
    RANGE_CACHE_BY_OPTS[opts] = {
        range = range,
        min = range.min,
        max = range.max,
        step = range.step,
        prepend = range.prepend,
        append = range.append,
        prefix = range.prefix,
        suffix = range.suffix,
        values = values,
        displayValues = displayValues,
    }
    return values, displayValues
end

local function ChoiceDisplay(opts, rangeDisplayValues, value)
    if value == nil then
        return ""
    end
    if opts.displayValues and opts.displayValues[value] ~= nil then
        return tostring(opts.displayValues[value])
    end
    if rangeDisplayValues and rangeDisplayValues[value] ~= nil then
        return tostring(rangeDisplayValues[value])
    end
    return tostring(value)
end

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

local function EndLabeledDropdownControl(imgui, opts, pushedWidth)
    if pushedWidth then
        imgui.PopItemWidth()
    end
    helpers.ShowTooltip(imgui, opts.tooltip)
end

local function GetDropdownPreview(opts, rangeDisplayValues, current, valueColors)
    return ChoiceDisplay(opts, rangeDisplayValues, current), valueColors and valueColors[current] or nil
end

function widgets.dropdown(imgui, field, opts)
    opts = opts or helpers.EMPTY_OPTS
    local controlId = opts.id or field:controlId()
    local values, rangeDisplayValues = ResolveDropdownChoices(opts)
    local current = field:read()
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local previewText, previewColor = GetDropdownPreview(opts, rangeDisplayValues, current, valueColors)
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
            if helpers.IsChoiceVisible(opts, value) then
                local label = ChoiceDisplay(opts, rangeDisplayValues, value)
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
        end
        imgui.EndCombo()
    end
    EndLabeledDropdownControl(imgui, opts, pushedWidth)
    return changed
end

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

function widgets.getPackedChoiceAlias(field, opts)
    opts = opts or helpers.EMPTY_OPTS
    local children = helpers.ResolvePackedChildren(field)
    local selection = helpers.ClassifyPackedChoice(opts, field, children)
    return selection.selectedChild and selection.selectedChild.alias or nil
end

return widgets
