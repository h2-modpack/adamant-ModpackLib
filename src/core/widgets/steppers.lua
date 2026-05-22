local helpers = ...
local widgets = {}

---@class StepperOpts
---@field id string|number|nil
---@field label string|nil
---@field default number|nil
---@field min number|nil
---@field max number|nil
---@field step number|nil
---@field displayValues table<number, string>|nil
---@field valueWidth number|nil
---@field buttonSpacing number|nil
---@field action DrawActionRef|nil
---@field value any

---@class SteppedRangeOpts: StepperOpts
---@field defaultMax number|nil
---@field rangeGap number|nil

local function NormalizeStepperValue(value, defaultValue, minValue, maxValue)
    local num = tonumber(value)
    if num == nil then
        num = tonumber(defaultValue) or 0
    end
    num = math.floor(num)
    if minValue ~= nil and num < minValue then num = minValue end
    if maxValue ~= nil and num > maxValue then num = maxValue end
    return num
end

local function NormalizeStep(step)
    return math.floor(tonumber(step) or 1)
end

local function GetValueText(value, displayValues)
    local displayValue = displayValues and displayValues[value]
    return tostring(displayValue ~= nil and displayValue or value)
end

local function DrawCenteredValue(imgui, value, displayValues, valueWidth)
    local valueText = GetValueText(value, displayValues)
    local measuredWidth = imgui.CalcTextSize(valueText)
    local textWidth = type(measuredWidth) == "table" and measuredWidth.x or measuredWidth

    imgui.AlignTextToFramePadding()
    if valueWidth and valueWidth > 0 then
        local startX = imgui.GetCursorPosX()
        local offset = math.max((valueWidth - textWidth) / 2, 0)
        imgui.SetCursorPosX(startX + offset)
        imgui.Text(valueText)
        if textWidth + offset < valueWidth then
            imgui.SameLine()
            imgui.Dummy(valueWidth - textWidth - offset, 0)
        end
    else
        imgui.Text(valueText)
    end
end

local function CommitStepperValue(field, currentValue, nextValue, defaultValue, minValue, maxValue)
    local normalized = NormalizeStepperValue(nextValue, defaultValue, minValue, maxValue)
    if normalized ~= currentValue then
        field:write(normalized)
        return true, normalized
    end
    return false, currentValue
end

local function DrawStepperControl(imgui, field, id, renderedValue, opts, minValue, maxValue)
    local changed = false
    local currentValue = renderedValue
    local step = NormalizeStep(opts.step)
    local gap = helpers.ResolveGap(imgui, opts.buttonSpacing)
    local valueWidth = tonumber(opts.valueWidth)

    if imgui.Button("-##" .. tostring(id) .. "_dec") and (minValue == nil or currentValue > minValue) then
        local wrote
        wrote, currentValue = CommitStepperValue(
            field,
            currentValue,
            currentValue - step,
            opts.default,
            minValue,
            maxValue
        )
        changed = wrote or changed
    end

    helpers.SameLineWithGap(imgui, gap)
    DrawCenteredValue(imgui, currentValue, opts.displayValues, valueWidth)

    helpers.SameLineWithGap(imgui, gap)
    if imgui.Button("+##" .. tostring(id) .. "_inc") and (maxValue == nil or currentValue < maxValue) then
        local wrote
        wrote, currentValue = CommitStepperValue(
            field,
            currentValue,
            currentValue + step,
            opts.default,
            minValue,
            maxValue
        )
        changed = wrote or changed
    end

    return changed, currentValue
end

---@param imgui table
---@param field StorageField
---@param opts StepperOpts|nil
---@return boolean
function widgets.stepper(imgui, field, opts)
    opts = opts or helpers.EMPTY_OPTS
    local id = opts.id ~= nil and tostring(opts.id) or field:controlId()
    local minValue = opts.min
    local maxValue = opts.max
    local renderedValue = NormalizeStepperValue(field:read(), opts.default, minValue, maxValue)

    local label = tostring(opts.label or "")
    if label ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(label)
        helpers.SameLineWithGap(imgui, helpers.ResolveGap(imgui, opts.buttonSpacing))
    end

    local changed = DrawStepperControl(imgui, field, id, renderedValue, opts, minValue, maxValue)
    if changed then
        helpers.StageAction("draw.widgets.stepper", opts, field:read())
    end
    return changed
end

---@param imgui table
---@param minField StorageField
---@param maxField StorageField
---@param opts SteppedRangeOpts|nil
---@return boolean
function widgets.steppedRange(imgui, minField, maxField, opts)
    opts = opts or helpers.EMPTY_OPTS
    local minFieldControlId = minField:controlId()
    local maxFieldControlId = maxField:controlId()
    local minValue = NormalizeStepperValue(minField:read(), opts.default, opts.min, opts.max)
    local maxValue = NormalizeStepperValue(maxField:read(), opts.defaultMax or opts.default, opts.min, opts.max)
    local changed = false
    local rangeGap = helpers.ResolveGap(imgui, opts.rangeGap)

    if type(opts.label) == "string" and opts.label ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(opts.label)
        helpers.SameLineWithGap(imgui, rangeGap)
    end

    local minChanged
    minChanged, minValue = DrawStepperControl(
        imgui,
        minField,
        tostring(minFieldControlId) .. "_min",
        minValue,
        opts,
        opts.min,
        maxValue
    )
    changed = minChanged or changed

    helpers.SameLineWithGap(imgui, rangeGap)
    imgui.AlignTextToFramePadding()
    imgui.Text("to")

    helpers.SameLineWithGap(imgui, rangeGap)
    local maxChanged
    maxChanged = DrawStepperControl(
        imgui,
        maxField,
        tostring(maxFieldControlId) .. "_max",
        maxValue,
        opts,
        minValue,
        opts.max
    )
    changed = maxChanged or changed

    if changed then
        helpers.StageAction("draw.widgets.steppedRange", opts, {
            min = minField:read(),
            max = maxField:read(),
        })
    end
    return changed
end

return widgets
