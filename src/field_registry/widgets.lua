local internal = AdamantModpackLib_Internal
local shared = internal.shared
local StorageTypes = shared.StorageTypes
local WidgetTypes = shared.WidgetTypes
local libWarn = shared.libWarn
local registry = shared.fieldRegistry

local NormalizeInteger = registry.NormalizeInteger
local NormalizeChoiceValue = registry.NormalizeChoiceValue
local NormalizeColor = registry.NormalizeColor
local PrepareWidgetText = registry.PrepareWidgetText
local ChoiceDisplay = registry.ChoiceDisplay
local GetCursorPosXSafe = registry.GetCursorPosXSafe
local GetStyleMetricX = registry.GetStyleMetricX
local CalcTextWidth = registry.CalcTextWidth
-- local EstimateButtonWidth = registry.EstimateButtonWidth
local DrawWidgetSlots = registry.DrawWidgetSlots
local GetSlotGeometry = registry.GetSlotGeometry
local ShowPreparedTooltip = registry.ShowPreparedTooltip
local AlignSlotContent = registry.AlignSlotContent

local DEFAULT_PACKED_SLOT_COUNT = 32

local function BuildIndexedSlots(count, buildSlot)
    local slots = {}
    for index = 1, count do
        slots[index] = buildSlot(index)
    end
    return slots
end

local function WarnIgnoredSlotKeys(prefix, geometry, slotName, keys, widgetTypeName)
    local slot = type(geometry) == "table" and geometry[slotName] or nil
    if type(slot) ~= "table" then
        return
    end
    for _, key in ipairs(keys) do
        if slot[key] ~= nil then
            libWarn("%s: geometry slot '%s' %s is ignored by widget type '%s'",
                prefix, tostring(slotName), tostring(key), tostring(widgetTypeName))
        end
    end
end

local function WarnIgnoredDynamicSlotKeys(prefix, geometry, pattern, keys, widgetTypeName)
    if type(geometry) ~= "table" then
        return
    end
    for slotName, slot in pairs(geometry) do
        if type(slotName) == "string" and string.match(slotName, pattern) and type(slot) == "table" then
            for _, key in ipairs(keys) do
                if slot[key] ~= nil then
                    libWarn("%s: geometry slot '%s' %s is ignored by widget type '%s'",
                        prefix, tostring(slotName), tostring(key), tostring(widgetTypeName))
                end
            end
        end
    end
end

local function CreateStepperSlotTemplate(node, options)
    options = options or {}
    local fastStep = node._fastStep
    local label = node._label or ""
    local hasLabel = options.drawLabel ~= false and label ~= ""
    local firstSlotSameLine = options.firstSlotSameLine == true or hasLabel
    local slotPrefix = options.slotPrefix or ""
    local labelSlotName = options.labelSlotName or "label"

    local function SlotName(name)
        if slotPrefix ~= "" then
            return slotPrefix .. name
        end
        return name
    end

    local function GetStepperLimits()
        local ctx = node._stepperCtx
        local minValue = ctx and ctx.min ~= nil and ctx.min or node.min
        local maxValue = ctx and ctx.max ~= nil and ctx.max or node.max
        return minValue, maxValue
    end

    local function CommitValue(nextValue)
        local ctx = node._stepperCtx
        if not ctx or not ctx.boundValue then
            return false
        end
        local minValue, maxValue = GetStepperLimits()
        local normalized = NormalizeInteger(node, nextValue)
        if minValue ~= nil and normalized < minValue then
            normalized = minValue
        end
        if maxValue ~= nil and normalized > maxValue then
            normalized = maxValue
        end
        if normalized ~= ctx.renderedValue then
            ctx.renderedValue = normalized
            ctx.boundValue:set(normalized)
            return true
        end
        return false
    end

    local slots = {}

    if hasLabel then
        table.insert(slots, {
            name = labelSlotName,
            draw = function(imgui)
                imgui.Text(label)
                ShowPreparedTooltip(imgui, node)
                return false
            end,
        })
    end

    table.insert(slots, {
        name = SlotName("decrement"),
        sameLine = firstSlotSameLine,
        draw = function(imgui)
            local ctx = node._stepperCtx
            local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
            local minValue = GetStepperLimits()
            if imgui.Button("-") and renderedValue > minValue then
                return CommitValue(renderedValue - (node._step or 1))
            end
            return false
        end,
    })

    table.insert(slots, {
        name = SlotName("value"),
        sameLine = true,
        draw = function(imgui, slot)
            local ctx = node._stepperCtx
            local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
            ctx.valueSlotStart = GetCursorPosXSafe(imgui)
            ctx.valueSlotWidth = slot.width
            if node._lastStepperVal ~= renderedValue then
                node._lastStepperStr = tostring(renderedValue)
                node._lastStepperVal = renderedValue
            end
            local valueText = node._lastStepperStr
            AlignSlotContent(imgui, slot, CalcTextWidth(imgui, valueText))
            imgui.Text(valueText)
            return false
        end,
    })

    table.insert(slots, {
        name = SlotName("increment"),
        sameLine = true,
        draw = function(imgui, slot)
            local ctx = node._stepperCtx
            local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
            local _, maxValue = GetStepperLimits()
            local style = imgui.GetStyle()
            local itemSpacingX = GetStyleMetricX(style, "ItemSpacing", 0)
            if slot.start == nil and ctx.valueSlotWidth and ctx.valueSlotStart ~= nil then
                imgui.SetCursorPosX(ctx.valueSlotStart + ctx.valueSlotWidth + itemSpacingX)
            end
            if imgui.Button("+") and renderedValue < maxValue then
                return CommitValue(renderedValue + (node._step or 1))
            end
            return false
        end,
    })

    if fastStep then
        table.insert(slots, {
            name = SlotName("fastDecrement"),
            sameLine = true,
            draw = function(imgui)
                local ctx = node._stepperCtx
                local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
                local minValue = GetStepperLimits()
                if imgui.Button("<<") and renderedValue > minValue then
                    return CommitValue(renderedValue - fastStep)
                end
                return false
            end,
        })
        table.insert(slots, {
            name = SlotName("fastIncrement"),
            sameLine = true,
            draw = function(imgui)
                local ctx = node._stepperCtx
                local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
                local _, maxValue = GetStepperLimits()
                if imgui.Button(">>") and renderedValue < maxValue then
                    return CommitValue(renderedValue + fastStep)
                end
                return false
            end,
        })
    end

    return slots
end

local function PrepareStepperDrawContext(node, boundValue, limits)
    local ctx = node._stepperCtx or {}
    ctx.boundValue = boundValue
    ctx.renderedValue = NormalizeInteger(node, boundValue:get())
    ctx.min = limits and limits.min or node.min
    ctx.max = limits and limits.max or node.max
    ctx.valueSlotStart = nil
    ctx.valueSlotWidth = nil
    node._stepperCtx = ctx
end

WidgetTypes.checkbox = {
    binds = { value = { storageType = "bool" } },
    slots = { "control" },
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "boolean" then
            libWarn("%s: checkbox default must be boolean, got %s", prefix, type(node.default))
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
        node._checkboxSlots = {
            {
                name = "control",
                draw = function(imgui)
                    local value = node._checkboxValue == true
                    local newVal, changed = imgui.Checkbox((node._label or "") .. (node._imguiId or ""), value)
                    ShowPreparedTooltip(imgui, node)
                    if changed then
                        node._checkboxBound:set(newVal)
                        return true
                    end
                    return false
                end,
            },
        }
    end,
    draw = function(imgui, node, bound)
        node._checkboxBound = bound.value
        node._checkboxValue = bound.value:get()
        if node._checkboxValue == nil then node._checkboxValue = node.default == true end
        return DrawWidgetSlots(imgui, node, node._checkboxSlots, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.text = {
    binds = {},
    slots = { "value" },
    validate = function(node, prefix)
        if node.text ~= nil and type(node.text) ~= "string" then
            libWarn("%s: text text must be string", prefix)
        end
        if node.label ~= nil and type(node.label) ~= "string" then
            libWarn("%s: text label must be string", prefix)
        end
        if node.color ~= nil then
            if type(node.color) ~= "table" then
                libWarn("%s: text color must be a table", prefix)
            else
                local count = 0
                for i = 1, 4 do
                    if node.color[i] ~= nil then
                        count = count + 1
                        if type(node.color[i]) ~= "number" then
                            libWarn("%s: text color[%d] must be a number", prefix, i)
                        end
                    end
                end
                if count ~= 3 and count ~= 4 then
                    libWarn("%s: text color must have 3 or 4 numeric entries", prefix)
                end
            end
        end
        node._text = tostring(node.text or node.label or "")
        node._color = NormalizeColor(node.color)
        PrepareWidgetText(node)
        node._textSlots = {
            {
                name = "value",
                draw = function(imgui, slot)
                    local text = node._text or ""
                    local color = node._color
                    AlignSlotContent(imgui, slot, CalcTextWidth(imgui, text))
                    if type(color) == "table" then
                        imgui.TextColored(color[1], color[2], color[3], color[4], text)
                    else
                        imgui.Text(text)
                    end
                    ShowPreparedTooltip(imgui, node)
                    return false
                end,
            },
        }
    end,
    draw = function(imgui, node)
        return DrawWidgetSlots(imgui, node, node._textSlots, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.dropdown = {
    binds = { value = { storageType = "string" } },
    slots = { "label", "control" },
    validate = function(node, prefix)
        if not node.values then
            libWarn("%s: dropdown missing values list", prefix)
        elseif type(node.values) ~= "table" or #node.values == 0 then
            libWarn("%s: dropdown values must be a non-empty list", prefix)
        else
            for _, value in ipairs(node.values) do
                if type(value) == "string" and string.find(value, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, value)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: dropdown displayValues must be a table", prefix)
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
        local hasLabel = (node._label or "") ~= ""
        node._dropdownSlots = {
            {
                name = "label",
                hidden = not hasLabel,
                draw = function(imgui)
                    imgui.Text(node._label or "")
                    ShowPreparedTooltip(imgui, node)
                    return false
                end,
            },
            {
                name = "control",
                sameLine = hasLabel,
                draw = function(imgui)
                    local ctx = node._dropdownCtx or {}
                    if imgui.BeginCombo(node._imguiId, ChoiceDisplay(node, ctx.previewValue or "")) then
                        for index, candidate in ipairs(node.values or {}) do
                            if imgui.Selectable(ChoiceDisplay(node, candidate), index == ctx.currentIdx) then
                                if candidate ~= ctx.current then
                                    ctx.boundValue:set(candidate)
                                    return true
                                end
                            end
                        end
                        imgui.EndCombo()
                    end
                    return false
                end,
            },
        }
    end,
    draw = function(imgui, node, bound, width)
        local current = NormalizeChoiceValue(node, bound.value:get())
        local currentIdx = 1
        for index, candidate in ipairs(node.values or {}) do
            if candidate == current then currentIdx = index; break end
        end

        local ctx = node._dropdownCtx or {}
        ctx.boundValue = bound.value
        ctx.current = current
        ctx.currentIdx = currentIdx
        ctx.previewValue = (node.values and node.values[currentIdx]) or ""
        node._dropdownCtx = ctx
        node._dropdownSlots[2].width = width

        return DrawWidgetSlots(imgui, node, node._dropdownSlots, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.radio = {
    binds = { value = { storageType = "string" } },
    slots = { "label" },
    dynamicSlots = function(node, slotName)
        local optionIndex = type(slotName) == "string" and tonumber(string.match(slotName, "^option:(%d+)$")) or nil
        if optionIndex == nil then
            return false, nil
        end
        local optionCount = type(node.values) == "table" and #node.values or 0
        if optionIndex < 1 or optionIndex > optionCount then
            return false, ("geometry slot '%s' is out of range for %d radio options"):format(
                tostring(slotName), optionCount)
        end
        return true, nil
    end,
    validate = function(node, prefix)
        if not node.values then
            libWarn("%s: radio missing values list", prefix)
        elseif type(node.values) ~= "table" or #node.values == 0 then
            libWarn("%s: radio values must be a non-empty list", prefix)
        else
            for _, value in ipairs(node.values) do
                if type(value) == "string" and string.find(value, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, value)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: radio displayValues must be a table", prefix)
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
        local label = node._label or ""
        local slots = {}
        if label ~= "" then
            table.insert(slots, {
                name = "label",
                draw = function(imgui)
                    imgui.Text(label)
                    ShowPreparedTooltip(imgui, node)
                    return false
                end,
            })
        end
        local optionValues = node.values or {}
        local optionSlots = BuildIndexedSlots(#optionValues, function(index)
            local candidate = optionValues[index]
            return {
                name = "option:" .. tostring(index),
                sameLine = label == "" and index > 1,
                draw = function(imgui)
                    local ctx = node._radioCtx or {}
                    if imgui.RadioButton(ChoiceDisplay(node, candidate), ctx.current == candidate) then
                        if candidate ~= ctx.current then
                            ctx.boundValue:set(candidate)
                            return true
                        end
                    end
                    return false
                end,
            }
        end)
        for _, slot in ipairs(optionSlots) do
            table.insert(slots, slot)
        end
        node._radioSlots = slots
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredSlotKeys(prefix, geometry, "label", { "width", "align" }, "radio")
        WarnIgnoredDynamicSlotKeys(prefix, geometry, "^option:%d+$", { "width", "align" }, "radio")
    end,
    draw = function(imgui, node, bound)
        local ctx = node._radioCtx or {}
        ctx.boundValue = bound.value
        ctx.current = NormalizeChoiceValue(node, bound.value:get())
        node._radioCtx = ctx
        local changed = DrawWidgetSlots(imgui, node, node._radioSlots, GetCursorPosXSafe(imgui))
        if (node._label or "") == "" then
            imgui.NewLine()
        end
        return changed
    end,
}

local function ValidateStepper(node, prefix)
    StorageTypes.int.validate(node, prefix)
    if node.step ~= nil and (type(node.step) ~= "number" or node.step <= 0) then
        libWarn("%s: stepper step must be a positive number", prefix)
    end
    if node.fastStep ~= nil and (type(node.fastStep) ~= "number" or node.fastStep <= 0) then
        libWarn("%s: stepper fastStep must be a positive number", prefix)
    end
    node._step = math.floor(tonumber(node.step) or 1)
    node._fastStep = node.fastStep and math.floor(node.fastStep) or nil
    PrepareWidgetText(node, node.binds and node.binds.value)
    node._slotTemplate = CreateStepperSlotTemplate(node)
end

WidgetTypes.stepper = {
    binds = { value = { storageType = "int" } },
    slots = { "label", "decrement", "value", "increment", "fastDecrement", "fastIncrement" },
    validate = ValidateStepper,
    draw = function(imgui, node, bound)
        PrepareStepperDrawContext(node, bound.value)
        return DrawWidgetSlots(imgui, node, node._slotTemplate, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.steppedRange = {
    binds = {
        min = { storageType = "int" },
        max = { storageType = "int" },
    },
    slots = {
        "label",
        "min.decrement", "min.value", "min.increment", "min.fastDecrement", "min.fastIncrement",
        "separator",
        "max.decrement", "max.value", "max.increment", "max.fastDecrement", "max.fastIncrement",
    },
    validate = function(node, prefix)
        local minStepper = {
            label = node.label,
            default = node.default,
            min = node.min, max = node.max,
            step = node.step, fastStep = node.fastStep,
        }
        local maxStepper = {
            default = node.defaultMax or node.default,
            min = node.min, max = node.max,
            step = node.step, fastStep = node.fastStep,
        }
        ValidateStepper(minStepper, prefix .. " min")
        ValidateStepper(maxStepper, prefix .. " max")
        minStepper._slotTemplate = CreateStepperSlotTemplate(minStepper, {
            drawLabel = true,
            slotPrefix = "min.",
            labelSlotName = "label",
        })
        maxStepper._slotTemplate = CreateStepperSlotTemplate(maxStepper, {
            drawLabel = false,
            slotPrefix = "max.",
            firstSlotSameLine = true,
        })
        node._minStepper = minStepper
        node._maxStepper = maxStepper
        node._rangeSlots = {}
        for _, slot in ipairs(minStepper._slotTemplate) do
            table.insert(node._rangeSlots, slot)
        end
        table.insert(node._rangeSlots, {
            name = "separator",
            sameLine = true,
            draw = function(imgui, slot)
                local ctx = node._rangeCtx or {}
                local separatorText = "to"
                local separatorWidth = CalcTextWidth(imgui, separatorText)
                if slot.start == nil then
                    local beforeMax = GetSlotGeometry(node, "max.decrement")
                    if beforeMax and type(beforeMax.start) == "number" then
                        local afterMin = GetCursorPosXSafe(imgui)
                        local separatorX = afterMin
                            + math.max(((ctx.rowStart + beforeMax.start) - afterMin - separatorWidth) / 2, 0)
                        imgui.SetCursorPosX(separatorX)
                    end
                end
                AlignSlotContent(imgui, slot, separatorWidth)
                imgui.Text(separatorText)
                return false
            end,
        })
        for _, slot in ipairs(maxStepper._slotTemplate) do
            table.insert(node._rangeSlots, slot)
        end
    end,
    draw = function(imgui, node, bound)
        local minStepper = node._minStepper
        local maxStepper = node._maxStepper
        if not minStepper or not maxStepper then
            libWarn("steppedRange '%s' not prepared", tostring(node.binds and node.binds.min or node.type))
            return false
        end

        local minValue = bound.min:get()
        local maxValue = bound.max:get()

        local rowStart = GetCursorPosXSafe(imgui)
        node._rangeCtx = node._rangeCtx or {}
        node._rangeCtx.rowStart = rowStart
        PrepareStepperDrawContext(minStepper, bound.min, { min = minStepper.min, max = maxValue })
        PrepareStepperDrawContext(maxStepper, bound.max, { min = minValue, max = maxStepper.max })
        return DrawWidgetSlots(imgui, node, node._rangeSlots, rowStart)
    end,
}

WidgetTypes.packedCheckboxList = {
    binds = { value = { storageType = "int" } },
    dynamicSlots = function(node, slotName)
        local itemIndex = type(slotName) == "string" and tonumber(string.match(slotName, "^item:(%d+)$")) or nil
        if itemIndex == nil then
            return false, nil
        end
        local slotCount = tonumber(node.slotCount) or DEFAULT_PACKED_SLOT_COUNT
        slotCount = math.floor(slotCount)
        if itemIndex < 1 or itemIndex > slotCount then
            return false, ("geometry slot '%s' is out of range for packedCheckboxList slotCount %d"):format(
                tostring(slotName), slotCount)
        end
        return true, nil
    end,
    validate = function(node, prefix)
        if node.slotCount == nil then
            node.slotCount = DEFAULT_PACKED_SLOT_COUNT
        elseif type(node.slotCount) ~= "number" then
            libWarn("%s: packedCheckboxList slotCount must be a number", prefix)
            node.slotCount = DEFAULT_PACKED_SLOT_COUNT
        elseif node.slotCount < 1 or math.floor(node.slotCount) ~= node.slotCount then
            libWarn("%s: packedCheckboxList slotCount must be a positive integer", prefix)
            node.slotCount = DEFAULT_PACKED_SLOT_COUNT
        else
            node.slotCount = math.floor(node.slotCount)
        end

        node._packedSlots = BuildIndexedSlots(node.slotCount, function(index)
            return {
                name = "item:" .. tostring(index),
                line = index,
                hidden = false,
                draw = function(imgui)
                    local ctx = node._packedCtx or {}
                    local child = ctx.children and ctx.children[index] or nil
                    if not child then
                        return false
                    end
                    local val = child.get()
                    if val == nil then val = false end
                    local newVal, changed = imgui.Checkbox(child.label, val == true)
                    if changed then child.set(newVal) end
                    return changed
                end,
            }
        end)
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredDynamicSlotKeys(prefix, geometry, "^item:%d+$", { "width", "align" }, "packedCheckboxList")
    end,
    draw = function(imgui, node, bound)
        local children = bound.value and bound.value.children
        if not children or #children == 0 then
            libWarn("packedCheckboxList: no packed children for alias '%s'; bind to a packedInt root",
                tostring(node.binds and node.binds.value or "?"))
            return
        end

        node._packedCtx = node._packedCtx or {}
        node._packedCtx.children = children
        for index = 1, node.slotCount do
            local child = children[index]
            node._packedSlots[index].hidden = child == nil
        end
        return DrawWidgetSlots(imgui, node, node._packedSlots, GetCursorPosXSafe(imgui))
    end,
}
