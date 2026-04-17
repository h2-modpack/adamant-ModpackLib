local internal = AdamantModpackLib_Internal
local WidgetFns = public.widgets

local widgetHelpers = internal.widgetHelpers
local NormalizeChoiceValue = widgetHelpers.NormalizeChoiceValue
local ChoiceDisplay = widgetHelpers.ChoiceDisplay
local DrawWithValueColor = widgetHelpers.DrawWithValueColor
local MakeSelectableId = widgetHelpers.MakeSelectableId
local GetPackedChoiceLabel = widgetHelpers.GetPackedChoiceLabel
local ClassifyPackedChoice = widgetHelpers.ClassifyPackedChoice
local ApplyPackedChoiceSelection = widgetHelpers.ApplyPackedChoiceSelection
local ClearPackedChoiceSelection = widgetHelpers.ClearPackedChoiceSelection

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
---@field onSelect fun(option: MappedDropdownOption, uiState: UiState): boolean|nil

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

local function ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and imgui.IsItemHovered() then
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

---@param imgui table
---@param opts DropdownOpts|MappedDropdownOpts|PackedDropdownOpts
---@param previewText string
---@param previewColor Color|nil
---@param drawControl fun(controlWidth: number|nil, previewColor: Color|nil): boolean
---@return boolean
local function DrawLabeledDropdownControl(imgui, opts, previewText, previewColor, drawControl)
    local labelText = tostring(opts.label or "")
    local controlWidth = tonumber(opts.controlWidth)
    local controlGap = tonumber(opts.controlGap)
    if controlGap == nil or controlGap < 0 then
        controlGap = imgui.GetStyle().ItemSpacing.x
    end

    if labelText ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(labelText)
        ShowTooltip(imgui, opts.tooltip)
        imgui.SameLine()
        if controlGap > 0 then
            imgui.SetCursorPosX(imgui.GetCursorPosX() + controlGap)
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

---@param imgui table
---@param uiState UiState
---@param alias string
---@param opts DropdownOpts|nil
---@return boolean
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

---@param imgui table
---@param uiState UiState
---@param alias string
---@param opts MappedDropdownOpts|nil
---@return boolean
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

---@param imgui table
---@param uiState UiState
---@param alias string
---@param store ManagedStore|nil
---@param opts PackedDropdownOpts|nil
---@return boolean
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
                local isSelected = selection.selectedChild ~= nil and selection.selectedChild.alias == child.alias
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
