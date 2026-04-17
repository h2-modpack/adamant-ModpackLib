local internal = AdamantModpackLib_Internal
local ui = internal.ui
local widgets = internal.widgets
local WidgetFns = public.widgets

local NormalizeChoiceValue = ui.NormalizeChoiceValue
local ChoiceDisplay = widgets.ChoiceDisplay
local GetStyleMetricX = ui.GetStyleMetricX
local EstimateButtonWidth = ui.EstimateButtonWidth

local choiceHelpers = widgets.choiceHelpers
local DrawWithValueColor = choiceHelpers.DrawWithValueColor
local MakeSelectableId = choiceHelpers.MakeSelectableId
local GetPackedChoiceLabel = choiceHelpers.GetPackedChoiceLabel
local ClassifyPackedChoice = choiceHelpers.ClassifyPackedChoice
local ApplyPackedChoiceSelection = choiceHelpers.ApplyPackedChoiceSelection
local ClearPackedChoiceSelection = choiceHelpers.ClearPackedChoiceSelection

local function ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and type(imgui.IsItemHovered) == "function" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
end

local function ResolvePackedChildren(uiState, alias, store)
    local aliasNode = uiState and uiState.getAliasNode and uiState.getAliasNode(alias) or nil
    local children = {}
    if store and type(store.getPackedAliases) == "function" then
        for _, child in ipairs(store.getPackedAliases(alias) or {}) do
            children[#children + 1] = {
                alias = child.alias,
                label = child.label or child.alias,
                get = function() return uiState.view[child.alias] end,
                set = function(value) uiState.set(child.alias, value) end,
            }
        end
        if #children > 0 then
            return children
        end
    end
    for _, child in ipairs(aliasNode and aliasNode._bitAliases or {}) do
        children[#children + 1] = {
            alias = child.alias,
            label = child.label or child.alias,
            get = function() return uiState.view[child.alias] end,
            set = function(value) uiState.set(child.alias, value) end,
        }
    end
    return children
end

local function DrawLabeledDropdownControl(imgui, opts, previewText, previewColor, drawControl)
    local labelText = tostring(opts.label or "")
    local controlWidth = tonumber(opts.controlWidth) or (EstimateButtonWidth(imgui, previewText) + 16)
    local controlGap = tonumber(opts.controlGap)
    if controlGap == nil or controlGap < 0 then
        controlGap = GetStyleMetricX(imgui.GetStyle(), "ItemSpacing", 8)
    end

    if labelText ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(labelText)
        ShowTooltip(imgui, opts.tooltip)
        imgui.SameLine()
        if controlGap > 0 then
            imgui.SetCursorPosX(ui.GetCursorPosXSafe(imgui) + controlGap)
        end
    end

    if controlWidth > 0 then
        imgui.PushItemWidth(controlWidth)
    end
    local changed = drawControl(controlWidth, previewColor) == true
    if controlWidth > 0 then
        imgui.PopItemWidth()
    end
    ShowTooltip(imgui, opts.tooltip)
    return changed
end

function WidgetFns.dropdown(imgui, uiState, alias, opts)
    opts = opts or {}
    local current = NormalizeChoiceValue(opts, uiState.view[alias])
    local optionEntries = {}
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    for index, value in ipairs(opts.values or {}) do
        optionEntries[#optionEntries + 1] = {
            value = value,
            label = ChoiceDisplay(opts, value),
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

    return DrawLabeledDropdownControl(imgui, opts, previewText, previewColor, function()
        local opened = DrawWithValueColor(imgui, previewColor, function()
            return imgui.BeginCombo("##" .. tostring(alias), previewText)
        end)
        if not opened then
            return false
        end
        local changed = false
        for _, option in ipairs(optionEntries) do
            local clicked = DrawWithValueColor(imgui, option.color, function()
                return imgui.Selectable(MakeSelectableId(option.label, option.uniqueId), option.value == current)
            end)
            if clicked and option.value ~= current then
                uiState.set(alias, option.value)
                current = option.value
                changed = true
            end
        end
        imgui.EndCombo()
        return changed
    end)
end

function WidgetFns.mappedDropdown(imgui, uiState, alias, opts)
    opts = opts or {}
    local preview = type(opts.getPreview) == "function"
        and tostring(opts.getPreview(uiState.view) or "")
        or tostring(uiState.view[alias] or "")
    local previewColor = type(opts.getPreviewColor) == "function" and opts.getPreviewColor(uiState.view) or nil
    local options = type(opts.getOptions) == "function"
        and (opts.getOptions(uiState.view) or {})
        or {}

    return DrawLabeledDropdownControl(imgui, opts, preview, previewColor, function()
        local opened = DrawWithValueColor(imgui, previewColor, function()
            return imgui.BeginCombo("##" .. tostring(alias), preview)
        end)
        if not opened then
            return false
        end
        local changed = false
        for _, option in ipairs(options) do
            local label = type(option) == "table" and tostring(option.label or option.value or "") or tostring(option)
            local optionColor = type(option) == "table" and option.color or nil
            local uniqueId = type(option) == "table" and (option.id or option.value or label) or option
            local clicked = DrawWithValueColor(imgui, optionColor, function()
                return imgui.Selectable(MakeSelectableId(label, uniqueId), false)
            end)
            if clicked then
                if type(option) == "table" and type(option.onSelect) == "function" then
                    changed = option.onSelect(option, uiState) == true or changed
                else
                    uiState.set(alias, type(option) == "table" and option.value or option)
                    changed = true
                end
            end
        end
        imgui.EndCombo()
        return changed
    end)
end

function WidgetFns.packedDropdown(imgui, uiState, alias, store, opts)
    opts = opts or {}
    local children = ResolvePackedChildren(uiState, alias, store)
    local selection = ClassifyPackedChoice(opts, children)
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local preview = tostring(opts.noneLabel or "None")
    local previewColor = nil
    if selection.state == "single" and selection.selectedChild then
        preview = GetPackedChoiceLabel(opts, selection.selectedChild)
        previewColor = valueColors and valueColors[selection.selectedChild.alias] or nil
    elseif selection.state == "multiple" then
        preview = tostring(opts.multipleLabel or "Multiple")
    end

    return DrawLabeledDropdownControl(imgui, opts, preview, previewColor, function()
        local opened = DrawWithValueColor(imgui, previewColor, function()
            return imgui.BeginCombo("##" .. tostring(alias), preview)
        end)
        if not opened then
            return false
        end
        local changed = false
        if imgui.Selectable(MakeSelectableId(tostring(opts.noneLabel or "None"), "none"), selection.state == "none") then
            changed = ClearPackedChoiceSelection(children, selection) or changed
        end
        for _, child in ipairs(children) do
            local childLabel = GetPackedChoiceLabel(opts, child)
            local childColor = valueColors and valueColors[child.alias] or nil
            local clicked = DrawWithValueColor(imgui, childColor, function()
                local isSelected = selection.selectedChild and selection.selectedChild.alias == child.alias
                return imgui.Selectable(MakeSelectableId(childLabel, child.alias), isSelected)
            end)
            if clicked then
                changed = ApplyPackedChoiceSelection(children, child.alias, selection) or changed
            end
        end
        imgui.EndCombo()
        return changed
    end)
end
