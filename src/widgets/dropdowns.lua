local helpers = ...
local WidgetFns = public.widgets
local imguiHelpers = public.imguiHelpers
---@class DropdownOpts
---@field label string|nil
---@field tooltip string|nil
---@field values ChoiceValue[]|nil
---@field default ChoiceValue|nil
---@field displayValues ChoiceDisplayValues|nil
---@field valueColors ValueColorMap|nil
---@field controlWidth number|nil
---@field controlGap number|nil

---@class MappedDropdownOption
---@field id string|number|nil
---@field label string|nil
---@field value any
---@field color Color|nil
---@field onSelect fun(option: MappedDropdownOption, session: Session): boolean|nil

---@class MappedDropdownOpts
---@field label string|nil
---@field tooltip string|nil
---@field controlWidth number|nil
---@field controlGap number|nil
---@field getPreview fun(view: table<string, any>): string|number|boolean|nil
---@field getPreviewColor fun(view: table<string, any>): Color|nil
---@field getOptions fun(view: table<string, any>): MappedDropdownOption[]|any[]

---@class PackedDropdownOpts
---@field label string|nil
---@field tooltip string|nil
---@field controlWidth number|nil
---@field controlGap number|nil
---@field displayValues ChoiceDisplayValues|nil
---@field valueColors table<string, Color>|nil
---@field noneLabel string|nil
---@field multipleLabel string|nil
---@field selectionMode PackedSelectionMode|nil

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
---@param opts DropdownOpts|MappedDropdownOpts|PackedDropdownOpts
---@param previewColor Color|nil
---@param drawControl fun(controlWidth: number|nil, previewColor: Color|nil): boolean
---@return boolean
local function DrawLabeledDropdownControl(imgui, opts, previewColor, drawControl)
    local labelText = tostring(opts.label or "")
    local controlWidth = tonumber(opts.controlWidth) or 0
    local controlGap = helpers.ResolveGap(imgui, opts.controlGap)

    if labelText ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(labelText)
        helpers.ShowTooltip(imgui, opts.tooltip)
        helpers.SameLineWithGap(imgui, controlGap)
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
---@param session Session
---@param alias string
---@param opts DropdownOpts|nil
---@return boolean
function WidgetFns.dropdown(imgui, session, alias, opts)
    opts = opts or {}
    local current = helpers.NormalizeChoiceValue(opts, session.read(alias))
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
            "##" .. tostring(alias),
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
                session.write(alias, option.value)
                current = option.value
                changed = true
            end
        end
        imgui.EndCombo()
        return changed
    end)
end

---@param imgui table
---@param session Session
---@param alias string
---@param opts MappedDropdownOpts|nil
---@return boolean
function WidgetFns.mappedDropdown(imgui, session, alias, opts)
    opts = opts or {}
    local preview = type(opts.getPreview) == "function"
        and tostring(opts.getPreview(session.view) or "")
        or tostring(session.read(alias) or "")
    local previewColor = type(opts.getPreviewColor) == "function" and opts.getPreviewColor(session.view) or nil
    local options = type(opts.getOptions) == "function"
        and (opts.getOptions(session.view) or {})
        or {}

    return DrawLabeledDropdownControl(imgui, opts, nil, function()
        local opened = imgui.BeginCombo(
            "##" .. tostring(alias),
            previewColor and "" or preview,
            COMBO_FLAG_NONE
        )
        if previewColor then
            DrawComboPreviewText(imgui, preview, previewColor)
        end
        if not opened then
            return false
        end
        local changed = false
        for _, option in ipairs(options) do
            local label = type(option) == "table" and tostring(option.label or option.value or "") or tostring(option)
            local optionColor = type(option) == "table" and option.color or nil
            local uniqueId = type(option) == "table" and (option.id or option.value or label) or option
            local clicked = helpers.DrawWithValueColor(imgui, optionColor, function()
                return imgui.Selectable(helpers.MakeSelectableId(label, uniqueId), false)
            end)
            if clicked then
                if type(option) == "table" and type(option.onSelect) == "function" then
                    changed = option.onSelect(option, session) == true or changed
                else
                    session.write(alias, type(option) == "table" and option.value or option)
                    changed = true
                end
            end
        end
        imgui.EndCombo()
        return changed
    end)
end

---@param imgui table
---@param session Session
---@param alias string
---@param store ManagedStore|nil
---@param opts PackedDropdownOpts|nil
---@return boolean
function WidgetFns.packedDropdown(imgui, session, alias, store, opts)
    opts = opts or {}
    local children = helpers.ResolvePackedChildren(session, alias, store)
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local selection = helpers.ClassifyPackedChoice(opts, children)
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
            "##" .. tostring(alias),
            "",
            COMBO_FLAG_NONE
        )
        DrawComboPreviewText(imgui, preview, previewColor)
        if not opened then
            return false
        end
        local changed = false
        local currentSelection = helpers.ClassifyPackedChoice(opts, children)
        if imgui.Selectable(
            helpers.MakeSelectableId(tostring(opts.noneLabel or "None"), "none"),
            currentSelection.state == "none"
        ) then
            changed = helpers.ClearPackedChoiceSelection(children, currentSelection) or changed
        end
        for _, child in ipairs(children) do
            local childLabel = helpers.GetPackedChoiceLabel(opts, child)
            local childColor = valueColors and valueColors[child.alias] or nil
            local clicked = helpers.DrawWithValueColor(imgui, childColor, function()
                local currentSelectionForChild = helpers.ClassifyPackedChoice(opts, children)
                local isSelected = currentSelectionForChild.selectedChild ~= nil
                    and currentSelectionForChild.selectedChild.alias == child.alias
                return imgui.Selectable(helpers.MakeSelectableId(childLabel, child.alias), isSelected)
            end)
            if clicked then
                changed = helpers.ApplyPackedChoiceSelection(children, child.alias, currentSelection) or changed
                currentSelection = helpers.ClassifyPackedChoice(opts, children)
            end
        end
        imgui.EndCombo()
        return changed
    end)
end
