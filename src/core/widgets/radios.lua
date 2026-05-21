local helpers = ...

---@class RadioOpts
---@field label string|nil
---@field values ChoiceValue[]|nil
---@field default ChoiceValue|nil
---@field displayValues ChoiceDisplayValues|nil
---@field valueColors ValueColorMap|nil
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

---@class RadioOptionEntry
---@field label string
---@field color Color|nil
---@field selected boolean
---@field onSelect fun(): boolean

---@param imgui table
---@param radioId string
---@param labelText string
---@param optionEntries RadioOptionEntry[]
---@param optionsPerLine number|nil
---@param optionGap number|nil
---@return boolean
local function DrawRadioOptions(imgui, radioId, labelText, optionEntries, optionsPerLine, optionGap)
    local changed = false
    local normalizedPerLine = math.floor(tonumber(optionsPerLine) or 0)
    if normalizedPerLine < 1 then
        normalizedPerLine = #optionEntries
    end
    local normalizedGap = helpers.ResolveGap(imgui, optionGap)

    if labelText ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(labelText)
    end

    for index, option in ipairs(optionEntries) do
        local positionInLine = (index - 1) % normalizedPerLine
        if positionInLine ~= 0 then
            helpers.SameLineWithGap(imgui, normalizedGap)
        end

        local clicked = helpers.DrawWithValueColor(imgui, option.color, function()
            return imgui.RadioButton(option.label .. "##" .. tostring(radioId) .. "_" .. tostring(index), option.selected == true)
        end)
        if clicked and type(option.onSelect) == "function" and option.onSelect() == true then
            changed = true
        end
    end

    return changed
end

---@param imgui table
---@param field StorageField
---@param opts RadioOpts|nil
---@return boolean
function helpers.widgets.radio(imgui, field, opts)
    opts = opts or {}
    local current = helpers.NormalizeChoiceValue(opts, field:read())
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local optionEntries = {}

    for _, value in ipairs(opts.values or {}) do
        optionEntries[#optionEntries + 1] = {
            label = helpers.ChoiceDisplay(opts, value),
            color = valueColors and valueColors[value] or nil,
            selected = current == value,
            onSelect = function()
                if current ~= value then
                    field:write(value)
                    current = value
                    helpers.StageAction("draw.widgets.radio", opts, value)
                    return true
                end
                return false
            end,
        }
    end

    return DrawRadioOptions(
        imgui,
        field:controlId(),
        tostring(opts.label or ""),
        optionEntries,
        opts.optionsPerLine,
        opts.optionGap
    )
end

---@param imgui table
---@param field StorageField
---@param opts PackedRadioOpts|nil
---@return boolean
function helpers.widgets.packedRadio(imgui, field, opts)
    opts = opts or {}
    local children = helpers.ResolvePackedChildren(field)
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local selection = helpers.ClassifyPackedChoice(opts, field, children)
    local optionEntries = {
        {
            label = tostring(opts.noneLabel or "None"),
            selected = selection.state == "none",
            onSelect = function()
                local changed = helpers.ClearPackedChoiceSelection(field, children, selection) == true
                if changed then
                    helpers.StageAction("draw.widgets.packedRadio", opts, false)
                end
                return changed
            end,
        },
    }

    for _, child in ipairs(children) do
        optionEntries[#optionEntries + 1] = {
            label = helpers.GetPackedChoiceLabel(opts, child),
            color = valueColors and valueColors[child.alias] or nil,
            selected = selection.selectedChild and selection.selectedChild.alias == child.alias or false,
            onSelect = function()
                local changed = helpers.ApplyPackedChoiceSelection(field, children, child.alias, selection) == true
                if changed then
                    helpers.StageAction("draw.widgets.packedRadio", opts, child.alias)
                end
                return changed
            end,
        }
    end

    return DrawRadioOptions(
        imgui,
        field:controlId(),
        tostring(opts.label or ""),
        optionEntries,
        opts.optionsPerLine,
        opts.optionGap
    )
end
