local helpers = ...
local widgets = {}

---@class RadioOpts
---@field label string|nil
---@field values ChoiceValue[]|nil
---@field default ChoiceValue|nil
---@field displayValues ChoiceDisplayValues|nil
---@field valueColors ValueColorMap|nil
---@field visibleValues ChoiceVisibilityMap|nil
---@field optionsPerLine number|nil
---@field optionGap number|nil
---@field action DrawActionRef|nil
---@field value any

---@class PackedRadioOpts
---@field label string|nil
---@field displayValues ChoiceDisplayValues|nil
---@field valueColors table<string, Color>|nil
---@field noneLabel string|nil
---@field selectionMode PackedSelectionMode|nil
---@field optionsPerLine number|nil
---@field optionGap number|nil
---@field action DrawActionRef|nil
---@field value any

---@param imgui table
---@param labelText string
local function DrawRadioLabel(imgui, labelText)
    if labelText ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(labelText)
    end
end

---@param imgui table
---@param optionCount number
---@param optionsPerLine number|nil
---@param optionGap number|nil
---@return number optionsPerLine
---@return number optionGap
local function ResolveRadioLayout(imgui, optionCount, optionsPerLine, optionGap)
    local normalizedPerLine = math.floor(tonumber(optionsPerLine) or 0)
    if normalizedPerLine < 1 then
        normalizedPerLine = optionCount > 0 and optionCount or 1
    end
    local normalizedGap = helpers.ResolveGap(imgui, optionGap)
    return normalizedPerLine, normalizedGap
end

local function AdvanceRadioOption(imgui, index, optionsPerLine, optionGap)
    local positionInLine = (index - 1) % optionsPerLine
    if positionInLine ~= 0 then
        helpers.SameLineWithGap(imgui, optionGap)
    end
end

---@param imgui table
---@param field StorageField
---@param opts RadioOpts|nil
---@return boolean
function widgets.radio(imgui, field, opts)
    opts = opts or helpers.EMPTY_OPTS
    local current = helpers.NormalizeChoiceValue(opts, field:read())
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local values = opts.values or helpers.EMPTY_LIST
    local radioId = field:controlId()
    local optionCount = 0
    for _, value in ipairs(values) do
        if helpers.IsChoiceVisible(opts, value) then
            optionCount = optionCount + 1
        end
    end
    local optionsPerLine, optionGap = ResolveRadioLayout(imgui, optionCount, opts.optionsPerLine, opts.optionGap)
    local visibleIndex = 0
    local changed = false

    DrawRadioLabel(imgui, tostring(opts.label or ""))
    for index, value in ipairs(values) do
        if helpers.IsChoiceVisible(opts, value) then
            visibleIndex = visibleIndex + 1
            AdvanceRadioOption(imgui, visibleIndex, optionsPerLine, optionGap)
            local label = helpers.ChoiceDisplay(opts, value)
            local color = valueColors and valueColors[value] or nil
            local clicked = helpers.RadioButtonWithValueColor(
                imgui,
                label .. "##" .. tostring(radioId) .. "_" .. tostring(index),
                current == value,
                color
            )
            if clicked and current ~= value then
                field:write(value)
                current = value
                helpers.StageAction("draw.widgets.radio", opts, value)
                changed = true
            end
        end
    end

    return changed
end

---@param imgui table
---@param field StorageField
---@param opts PackedRadioOpts|nil
---@return boolean
function widgets.packedRadio(imgui, field, opts)
    opts = opts or helpers.EMPTY_OPTS
    local children = helpers.ResolvePackedChildren(field)
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local selection = helpers.ClassifyPackedChoice(opts, field, children)
    local radioId = field:controlId()
    local optionCount = #children + 1
    local optionsPerLine, optionGap = ResolveRadioLayout(imgui, optionCount, opts.optionsPerLine, opts.optionGap)
    local changed = false
    local selectedChild = selection.selectedChild

    DrawRadioLabel(imgui, tostring(opts.label or ""))
    AdvanceRadioOption(imgui, 1, optionsPerLine, optionGap)
    if imgui.RadioButton(
        tostring(opts.noneLabel or "None") .. "##" .. tostring(radioId) .. "_1",
        selection.state == "none"
    ) then
        local cleared = helpers.ClearPackedChoiceSelection(field, children, selection) == true
        if cleared then
            helpers.StageAction("draw.widgets.packedRadio", opts, false)
        end
        changed = cleared or changed
        selectedChild = nil
    end

    for childIndex, child in ipairs(children) do
        local index = childIndex + 1
        AdvanceRadioOption(imgui, index, optionsPerLine, optionGap)
        local childColor = valueColors and valueColors[child.alias] or nil
        local clicked = helpers.RadioButtonWithValueColor(
            imgui,
            helpers.GetPackedChoiceLabel(opts, child) .. "##" .. tostring(radioId) .. "_" .. tostring(index),
            selectedChild ~= nil and selectedChild.alias == child.alias,
            childColor
        )
        if clicked then
            local selected = helpers.ApplyPackedChoiceSelection(field, children, child.alias, selection) == true
            if selected then
                helpers.StageAction("draw.widgets.packedRadio", opts, child.alias)
            end
            changed = selected or changed
            selectedChild = child
        end
    end

    return changed
end

return widgets
