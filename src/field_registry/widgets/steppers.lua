local internal = AdamantModpackLib_Internal
local ui = internal.ui
local WidgetFns = public.widgets

local NormalizeInteger = ui.NormalizeInteger
local CalcTextWidth = ui.CalcTextWidth
local EstimateButtonWidth = ui.EstimateButtonWidth
local EstimateStructuredRowAdvanceY = ui.EstimateStructuredRowAdvanceY
local DrawOrderedEntries = ui.DrawOrderedEntries
local GetStyleMetricX = ui.GetStyleMetricX

local function CompareEntries(left, right)
    if left.line ~= right.line then
        return left.line < right.line
    end
    if type(left.start) == "number" and type(right.start) == "number" and left.start ~= right.start then
        return left.start < right.start
    end
    return left.index < right.index
end

local function PrepareStepperDrawContext(node, boundValue, limits)
    local ctx = node._stepperCtx or {}
    ctx.boundValue = boundValue
    ctx.renderedValue = NormalizeInteger(node, boundValue:get())
    ctx.min = limits and limits.min or node.min
    ctx.max = limits and limits.max or node.max
    node._stepperCtx = ctx
end

local function BuildOrderedStepperEntries(node, options)
    options = options or {}
    local label = node.label or ""
    local hasLabel = options.drawLabel ~= false and label ~= ""
    local slotPrefix = options.slotPrefix or ""
    local geometryOwner = options.geometryOwner or node
    local entries = {}

    local function SlotName(name)
        return slotPrefix ~= "" and (slotPrefix .. name) or name
    end

    local function ControlGap(imgui)
        if type(geometryOwner.controlGap) == "number" and geometryOwner.controlGap >= 0 then
            return geometryOwner.controlGap
        end
        return GetStyleMetricX(imgui.GetStyle(), "ItemSpacing", 8)
    end

    local function AddEntry(name, config)
        entries[#entries + 1] = {
            index = #entries + 1,
            name = name,
            line = 1,
            start = config.start,
            width = config.width,
            align = config.align,
            estimateWidth = config.estimateWidth,
            render = config.render,
        }
    end

    local function GetStepperLimits()
        local ctx = node._stepperCtx
        local minValue = ctx and ctx.min ~= nil and ctx.min or node.min
        local maxValue = ctx and ctx.max ~= nil and ctx.max or node.max
        return minValue, maxValue
    end

    local function CommitValue(nextValue)
        local ctx = node._stepperCtx
        local minValue, maxValue = GetStepperLimits()
        local normalized = NormalizeInteger(node, nextValue)
        if minValue ~= nil and normalized < minValue then normalized = minValue end
        if maxValue ~= nil and normalized > maxValue then normalized = maxValue end
        if normalized ~= ctx.renderedValue then
            ctx.renderedValue = normalized
            ctx.boundValue:set(normalized)
            return true
        end
        return false
    end

    local function GetValueText()
        local ctx = node._stepperCtx
        local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
        local displayValue = node.displayValues and node.displayValues[renderedValue]
        return tostring(displayValue ~= nil and displayValue or renderedValue), renderedValue
    end

    if hasLabel then
        AddEntry("label", {
            estimateWidth = function(imgui) return CalcTextWidth(imgui, label) end,
            render = function(imgui)
                imgui.AlignTextToFramePadding()
                imgui.Text(label)
                return false, CalcTextWidth(imgui, label), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
        AddEntry(SlotName("gap"), {
            estimateWidth = function(imgui) return ControlGap(imgui) end,
            render = function(imgui)
                return false, ControlGap(imgui), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
    end

    AddEntry(SlotName("decrement"), {
        estimateWidth = function(imgui) return EstimateButtonWidth(imgui, "-") end,
        render = function(imgui)
            local ctx = node._stepperCtx
            local renderedValue = ctx.renderedValue
            local minValue = GetStepperLimits()
            local changed = imgui.Button("-") and renderedValue > minValue and CommitValue(renderedValue - (node.step or 1)) or false
            return changed, EstimateButtonWidth(imgui, "-"), EstimateStructuredRowAdvanceY(imgui)
        end,
    })

    AddEntry(SlotName("value"), {
        width = geometryOwner.valueWidth,
        align = geometryOwner.valueAlign,
        estimateWidth = function(imgui)
            return CalcTextWidth(imgui, GetValueText())
        end,
        render = function(imgui)
            local valueText = GetValueText()
            imgui.AlignTextToFramePadding()
            imgui.Text(valueText)
            return false, CalcTextWidth(imgui, valueText), EstimateStructuredRowAdvanceY(imgui)
        end,
    })

    AddEntry(SlotName("increment"), {
        estimateWidth = function(imgui) return EstimateButtonWidth(imgui, "+") end,
        render = function(imgui)
            local ctx = node._stepperCtx
            local renderedValue = ctx.renderedValue
            local _, maxValue = GetStepperLimits()
            local changed = imgui.Button("+") and renderedValue < maxValue and CommitValue(renderedValue + (node.step or 1)) or false
            return changed, EstimateButtonWidth(imgui, "+"), EstimateStructuredRowAdvanceY(imgui)
        end,
    })

    table.sort(entries, CompareEntries)
    return entries
end

local function PrepareOrderedRangeEntries(node, minStepper, maxStepper)
    local entries = BuildOrderedStepperEntries(minStepper, {
        drawLabel = true,
        slotPrefix = "min.",
        geometryOwner = node,
    })
    entries[#entries + 1] = {
        index = #entries + 1,
        name = "separator",
        line = 1,
        estimateWidth = function(_imgui) return CalcTextWidth(_imgui, "  to") end,
        render = function(_imgui)
            _imgui.AlignTextToFramePadding()
            _imgui.Text("  to")
            return false, CalcTextWidth(_imgui, "  to"), EstimateStructuredRowAdvanceY(_imgui)
        end,
    }
    local maxEntries = BuildOrderedStepperEntries(maxStepper, {
        drawLabel = false,
        slotPrefix = "max.",
        geometryOwner = node,
    })
    for _, entry in ipairs(maxEntries) do
        entry.index = #entries + 1
        entries[#entries + 1] = entry
    end
    table.sort(entries, CompareEntries)
    return entries
end

local function MakeStepperConfig(alias, opts)
    return {
        binds = { value = alias },
        label = tostring(opts.label or ""),
        default = opts.default,
        min = opts.min,
        max = opts.max,
        step = math.floor(tonumber(opts.step) or 1),
        fastStep = opts.fastStep and math.floor(tonumber(opts.fastStep)) or nil,
        displayValues = opts.displayValues,
        valueWidth = opts.valueWidth,
        valueAlign = opts.valueAlign,
        controlGap = opts.controlGap,
    }
end

function WidgetFns.stepper(imgui, uiState, alias, opts)
    opts = opts or {}
    local cfg = MakeStepperConfig(alias, opts)
    local boundValue = {
        get = function() return uiState.view[alias] end,
        set = function(value) uiState.set(alias, value) end,
    }
    PrepareStepperDrawContext(cfg, boundValue)
    local _, _, changed = DrawOrderedEntries(
        imgui,
        BuildOrderedStepperEntries(cfg),
        ui.GetCursorPosXSafe(imgui),
        ui.GetCursorPosYSafe(imgui),
        EstimateStructuredRowAdvanceY(imgui))
    return changed
end

function WidgetFns.steppedRange(imgui, uiState, minAlias, maxAlias, opts)
    opts = opts or {}
    local minStepper = MakeStepperConfig(minAlias, {
        label = opts.label,
        default = opts.default,
        min = opts.min,
        max = opts.max,
        step = opts.step,
        fastStep = opts.fastStep,
        valueWidth = opts.valueWidth,
        valueAlign = opts.valueAlign,
        controlGap = opts.controlGap,
    })
    local maxStepper = MakeStepperConfig(maxAlias, {
        default = opts.defaultMax or opts.default,
        min = opts.min,
        max = opts.max,
        step = opts.step,
        fastStep = opts.fastStep,
        valueWidth = opts.valueWidth,
        valueAlign = opts.valueAlign,
        controlGap = opts.controlGap,
    })
    local minBound = {
        get = function() return uiState.view[minAlias] end,
        set = function(value) uiState.set(minAlias, value) end,
    }
    local maxBound = {
        get = function() return uiState.view[maxAlias] end,
        set = function(value) uiState.set(maxAlias, value) end,
    }
    local minValue = minBound.get()
    local maxValue = maxBound.get()
    PrepareStepperDrawContext(minStepper, minBound, { min = minStepper.min, max = maxValue })
    PrepareStepperDrawContext(maxStepper, maxBound, { min = minValue, max = maxStepper.max })
    local _, _, changed = DrawOrderedEntries(
        imgui,
        PrepareOrderedRangeEntries(opts, minStepper, maxStepper),
        ui.GetCursorPosXSafe(imgui),
        ui.GetCursorPosYSafe(imgui),
        EstimateStructuredRowAdvanceY(imgui))
    return changed
end
