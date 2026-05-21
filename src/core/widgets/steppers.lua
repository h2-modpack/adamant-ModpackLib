local helpers = ...

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

local function MakeStepperConfig(opts)
    return {
        id = tostring(opts.id or ""),
        label = tostring(opts.label or ""),
        default = opts.default,
        min = opts.min,
        max = opts.max,
        step = math.floor(tonumber(opts.step) or 1),
        displayValues = opts.displayValues,
        valueWidth = tonumber(opts.valueWidth),
        buttonSpacing = opts.buttonSpacing,
    }
end

local function PrepareStepperDrawContext(node, boundValue, limits)
    local ctx = node._stepperCtx or {}
    ctx.boundValue = boundValue
    ctx.renderedValue = helpers.NormalizeInteger(node, boundValue:get())
    ctx.min = limits and limits.min or node.min
    ctx.max = limits and limits.max or node.max
    node._stepperCtx = ctx
    return ctx
end

local function GetStepperLimits(node)
    local ctx = node._stepperCtx
    local minValue = ctx and ctx.min ~= nil and ctx.min or node.min
    local maxValue = ctx and ctx.max ~= nil and ctx.max or node.max
    return minValue, maxValue
end

local function CommitStepperValue(node, nextValue)
    local ctx = node._stepperCtx
    local minValue, maxValue = GetStepperLimits(node)
    local normalized = helpers.NormalizeInteger(node, nextValue)
    if minValue ~= nil and normalized < minValue then normalized = minValue end
    if maxValue ~= nil and normalized > maxValue then normalized = maxValue end
    if normalized ~= ctx.renderedValue then
        ctx.renderedValue = normalized
        ctx.boundValue.set(normalized)
        return true
    end
    return false
end

local function GetValueText(node)
    local ctx = node._stepperCtx
    local renderedValue = ctx and ctx.renderedValue or helpers.NormalizeInteger(node, node.default)
    local displayValue = node.displayValues and node.displayValues[renderedValue]
    return tostring(displayValue ~= nil and displayValue or renderedValue), renderedValue
end

local function DrawCenteredValue(imgui, node)
    local valueText = GetValueText(node)
    local valueWidth = tonumber(node.valueWidth)
    local measuredWidth = imgui.CalcTextSize(tostring(valueText or ""))
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

local function DrawStepperControl(imgui, node)
    local changed = false
    local gap = helpers.ResolveGap(imgui, node.buttonSpacing)
    local renderedValue = node._stepperCtx.renderedValue
    local minValue, maxValue = GetStepperLimits(node)

    if imgui.Button("-##" .. tostring(node.id) .. "_dec") and (minValue == nil or renderedValue > minValue) then
        changed = CommitStepperValue(node, renderedValue - (node.step or 1)) or changed
    end

    helpers.SameLineWithGap(imgui, gap)
    DrawCenteredValue(imgui, node)

    helpers.SameLineWithGap(imgui, gap)
    if imgui.Button("+##" .. tostring(node.id) .. "_inc") and (maxValue == nil or renderedValue < maxValue) then
        changed = CommitStepperValue(node, renderedValue + (node.step or 1)) or changed
    end

    return changed
end

---@param imgui table
---@param field StorageField
---@param opts StepperOpts|nil
---@return boolean
function helpers.widgets.stepper(imgui, field, opts)
    opts = opts or {}
    local cfg = MakeStepperConfig(opts)
    cfg.id = cfg.id ~= "" and cfg.id or field:controlId()
    local boundValue = {
        get = function() return field:read() end,
        set = function(value) field:write(value) end,
    }
    PrepareStepperDrawContext(cfg, boundValue)

    local changed = false
    if cfg.label ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(cfg.label)
        local gap = helpers.ResolveGap(imgui, cfg.buttonSpacing)
        helpers.SameLineWithGap(imgui, gap)
    end
    changed = DrawStepperControl(imgui, cfg) or changed
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
function helpers.widgets.steppedRange(imgui, minField, maxField, opts)
    opts = opts or {}
    local minFieldControlId = minField:controlId()
    local maxFieldControlId = maxField:controlId()
    local minStepper = MakeStepperConfig({
        id = tostring(minFieldControlId) .. "_min",
        label = "",
        default = opts.default,
        min = opts.min,
        max = opts.max,
        step = opts.step,
        valueWidth = opts.valueWidth,
        buttonSpacing = opts.buttonSpacing,
    })
    local maxStepper = MakeStepperConfig({
        id = tostring(maxFieldControlId) .. "_max",
        label = "",
        default = opts.defaultMax or opts.default,
        min = opts.min,
        max = opts.max,
        step = opts.step,
        valueWidth = opts.valueWidth,
        buttonSpacing = opts.buttonSpacing,
    })
    local minBound = {
        get = function() return minField:read() end,
        set = function(value) minField:write(value) end,
    }
    local maxBound = {
        get = function() return maxField:read() end,
        set = function(value) maxField:write(value) end,
    }

    local minValue = minBound.get()
    local maxValue = maxBound.get()
    PrepareStepperDrawContext(minStepper, minBound, { min = minStepper.min, max = maxValue })
    PrepareStepperDrawContext(maxStepper, maxBound, { min = minValue, max = maxStepper.max })

    local changed = false
    local rangeGap = helpers.ResolveGap(imgui, opts.rangeGap)

    if type(opts.label) == "string" and opts.label ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(opts.label)
        helpers.SameLineWithGap(imgui, rangeGap)
    end

    changed = DrawStepperControl(imgui, minStepper) or changed

    helpers.SameLineWithGap(imgui, rangeGap)
    imgui.AlignTextToFramePadding()
    imgui.Text("to")

    helpers.SameLineWithGap(imgui, rangeGap)
    changed = DrawStepperControl(imgui, maxStepper) or changed

    if changed then
        helpers.StageAction("draw.widgets.steppedRange", opts, {
            min = minField:read(),
            max = maxField:read(),
        })
    end
    return changed
end
