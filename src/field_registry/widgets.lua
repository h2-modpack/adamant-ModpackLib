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
local EstimateButtonWidth = registry.EstimateButtonWidth
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

local function ValidateValueColorsTable(node, prefix, widgetName)
    node._valueColors = nil
    if node.valueColors == nil then
        return
    end
    if type(node.valueColors) ~= "table" then
        libWarn("%s: %s valueColors must be a table", prefix, widgetName)
        return
    end

    local normalizedColors = {}
    for key, color in pairs(node.valueColors) do
        local normalized = NormalizeColor(color)
        if normalized == nil then
            libWarn("%s: %s valueColors[%s] must be a 3- or 4-number color table", prefix, widgetName, tostring(key))
        else
            normalizedColors[key] = normalized
        end
    end
    node._valueColors = normalizedColors
end

local function DrawWithValueColor(imgui, color, drawFn)
    if type(color) ~= "table" or type(imgui.PushStyleColor) ~= "function" or type(imgui.PopStyleColor) ~= "function" then
        return drawFn()
    end

    local textEnum = imgui.ImGuiCol and imgui.ImGuiCol.Text or 0
    imgui.PushStyleColor(textEnum, color[1], color[2], color[3], color[4])
    local ok, a, b, c, d = pcall(drawFn)
    imgui.PopStyleColor()
    if not ok then
        error(a)
    end
    return a, b, c, d
end

local function MakeSelectableId(label, uniqueId)
    return tostring(label or "") .. "##" .. tostring(uniqueId or "")
end

local function ValidateDisplayValuesTable(node, prefix, widgetName)
    if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
        libWarn("%s: %s displayValues must be a table", prefix, widgetName)
    end
end

local function GetPackedChoiceMode(node)
    local mode = node.selectionMode
    if mode == nil or mode == "" then
        return "singleEnabled"
    end
    return mode
end

local function GetPackedChoiceChildren(node, bound, widgetName)
    local children = bound and bound.value and bound.value.children or nil
    if type(children) ~= "table" then
        libWarn("%s: no packed children for alias '%s'; bind to a packedInt root",
            widgetName, tostring(node.binds and node.binds.value))
        return nil
    end
    return children
end

local function GetPackedChoiceLabel(node, child)
    if type(node.displayValues) == "table" and node.displayValues[child.alias] ~= nil then
        return tostring(node.displayValues[child.alias])
    end
    return tostring(child.label or child.alias or "")
end

local function GetPackedChoiceNoneValue(mode)
    if mode == "singleRemaining" then
        return false
    end
    return false
end

local function IsPackedChoiceActive(mode, value)
    if mode == "singleRemaining" then
        return value == false
    end
    return value == true
end

local function GetPackedChoiceWriteValue(mode, isActive)
    if mode == "singleRemaining" then
        if isActive then
            return false
        end
        return true
    end
    return isActive == true
end

local function ClassifyPackedChoice(node, children)
    local mode = GetPackedChoiceMode(node)
    local noneValue = GetPackedChoiceNoneValue(mode)
    local activeCount = 0
    local totalCount = 0
    local lastActiveChild = nil

    for _, child in ipairs(children or {}) do
        totalCount = totalCount + 1
        local value = child.get and child.get() or noneValue
        if value == nil then
            value = noneValue
        end
        if IsPackedChoiceActive(mode, value) then
            activeCount = activeCount + 1
            lastActiveChild = child
        end
    end

    local state = "multiple"
    if activeCount == 0 then
        state = "none"
    elseif activeCount == 1 then
        state = "single"
    elseif mode == "singleRemaining" and activeCount == totalCount then
        state = "none"
    end

    return {
        state = state,
        selectedChild = state == "single" and lastActiveChild or nil,
        mode = mode,
        noneValue = noneValue,
    }
end

local function ApplyPackedChoiceSelection(children, selectedAlias, selection)
    local changed = false
    for _, child in ipairs(children or {}) do
        local shouldBeActive = child.alias == selectedAlias
        local nextValue = GetPackedChoiceWriteValue(selection.mode, shouldBeActive)
        local currentValue = child.get and child.get() or selection.noneValue
        if currentValue == nil then
            currentValue = selection.noneValue
        end
        if currentValue ~= nextValue then
            child.set(nextValue)
            changed = true
        end
    end
    return changed
end

local function ClearPackedChoiceSelection(children, selection)
    local changed = false
    for _, child in ipairs(children or {}) do
        local currentValue = child.get and child.get() or selection.noneValue
        if currentValue == nil then
            currentValue = selection.noneValue
        end
        if currentValue ~= selection.noneValue then
            child.set(selection.noneValue)
            changed = true
        end
    end
    return changed
end

local function ValidatePackedChoiceWidget(node, prefix, widgetName)
    local mode = GetPackedChoiceMode(node)
    if mode ~= "singleEnabled" and mode ~= "singleRemaining" then
        libWarn("%s: %s selectionMode must be 'singleEnabled' or 'singleRemaining'", prefix, widgetName)
    end
    if node.noneLabel ~= nil and type(node.noneLabel) ~= "string" then
        libWarn("%s: %s noneLabel must be a string", prefix, widgetName)
    end
    if node.multipleLabel ~= nil and type(node.multipleLabel) ~= "string" then
        libWarn("%s: %s multipleLabel must be a string", prefix, widgetName)
    end
    ValidateDisplayValuesTable(node, prefix, widgetName)
    ValidateValueColorsTable(node, prefix, widgetName)
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
            if ctx._lastStepperVal ~= renderedValue or ctx._lastStepperStr == nil then
                local displayValue = node.displayValues and node.displayValues[renderedValue]
                ctx._lastStepperStr = tostring(displayValue ~= nil and displayValue or renderedValue)
                ctx._lastStepperVal = renderedValue
            end
            local valueText = ctx._lastStepperStr
            AlignSlotContent(imgui, slot, CalcTextWidth(imgui, valueText))
            local color = node._valueColors and node._valueColors[renderedValue] or nil
            if type(color) == "table" then
                imgui.TextColored(color[1], color[2], color[3], color[4], valueText)
            else
                imgui.Text(valueText)
            end
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
    binds = { value = { storageType = "string", optional = true } },
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
                    local text = node._boundText ~= nil and tostring(node._boundText) or node._text or ""
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
    draw = function(imgui, node, bound)
        node._boundText = bound.value and bound.value:get() or nil
        return DrawWidgetSlots(imgui, node, node._textSlots, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.button = {
    binds = {},
    slots = { "control" },
    validate = function(node, prefix)
        PrepareWidgetText(node)
        if node._label == "" then
            libWarn("%s: button requires non-empty label", prefix)
        end
        if node.onClick ~= nil and type(node.onClick) ~= "function" then
            libWarn("%s: button onClick must be function", prefix)
        end
        node._buttonSlots = {
            {
                name = "control",
                draw = function(imgui, slot)
                    local label = (node._label or "") .. (node._imguiId or "")
                    AlignSlotContent(imgui, slot, EstimateButtonWidth(imgui, node._label or ""))
                    if imgui.Button(label) then
                        ShowPreparedTooltip(imgui, node)
                        return true
                    end
                    ShowPreparedTooltip(imgui, node)
                    return false
                end,
            },
        }
    end,
    draw = function(imgui, node, _, _, uiState)
        local changed = DrawWidgetSlots(imgui, node, node._buttonSlots, GetCursorPosXSafe(imgui))
        if changed and type(node.onClick) == "function" then
            node.onClick(uiState, node, imgui)
        end
        return changed
    end,
}

WidgetTypes.confirmButton = {
    binds = {},
    slots = { "control" },
    validate = function(node, prefix)
        PrepareWidgetText(node)
        if node._label == "" then
            libWarn("%s: confirmButton requires non-empty label", prefix)
        end
        if node.onConfirm ~= nil and type(node.onConfirm) ~= "function" then
            libWarn("%s: confirmButton onConfirm must be function", prefix)
        end
        if node.confirmLabel ~= nil and type(node.confirmLabel) ~= "string" then
            libWarn("%s: confirmButton confirmLabel must be string", prefix)
        end
        if node.cancelLabel ~= nil and type(node.cancelLabel) ~= "string" then
            libWarn("%s: confirmButton cancelLabel must be string", prefix)
        end
        if node.timeoutSeconds ~= nil and (type(node.timeoutSeconds) ~= "number" or node.timeoutSeconds <= 0) then
            libWarn("%s: confirmButton timeoutSeconds must be a positive number", prefix)
        end
        node._confirmLabel = type(node.confirmLabel) == "string" and node.confirmLabel ~= "" and node.confirmLabel or "Confirm"
        node._cancelLabel = type(node.cancelLabel) == "string" and node.cancelLabel ~= "" and node.cancelLabel or "Cancel"
        node._timeoutSeconds = type(node.timeoutSeconds) == "number" and node.timeoutSeconds > 0 and node.timeoutSeconds or 3
        node._confirmButtonSlots = {
            {
                name = "control",
                draw = function(imgui, slot)
                    local state = node._confirmButtonState or {}
                    if state.armed == true then
                        local confirmLabel = node._confirmLabel .. (node._imguiId or "")
                        if imgui.Button(confirmLabel) then
                            state.armed = false
                            state.expiresAt = nil
                            node._confirmButtonState = state
                            if type(node.onConfirm) == "function" then
                                node.onConfirm(state.uiState, node, imgui)
                            end
                            ShowPreparedTooltip(imgui, node)
                            return true
                        end
                        ShowPreparedTooltip(imgui, node)
                        imgui.SameLine()
                        if imgui.Button(node._cancelLabel .. "##cancel" .. (node._imguiId or "")) then
                            state.armed = false
                            state.expiresAt = nil
                            node._confirmButtonState = state
                            ShowPreparedTooltip(imgui, node)
                            return false
                        end
                        ShowPreparedTooltip(imgui, node)
                        imgui.SameLine()
                        local remaining = math.max(0, (state.expiresAt or 0) - (state.now or 0))
                        local statusText = string.format("Confirmation expires in %.1fs", remaining)
                        imgui.TextDisabled(statusText)
                        ShowPreparedTooltip(imgui, node)
                        return false
                    end

                    AlignSlotContent(imgui, slot, EstimateButtonWidth(imgui, node._label or ""))
                    if imgui.Button((node._label or "") .. (node._imguiId or "")) then
                        state.armed = true
                        state.expiresAt = (state.now or os.clock()) + node._timeoutSeconds
                        node._confirmButtonState = state
                        ShowPreparedTooltip(imgui, node)
                        return false
                    end
                    ShowPreparedTooltip(imgui, node)
                    return false
                end,
            },
        }
    end,
    draw = function(imgui, node, _, _, uiState)
        local state = node._confirmButtonState or {}
        state.uiState = uiState
        state.now = os.clock()
        if state.armed == true and state.expiresAt ~= nil and state.now >= state.expiresAt then
            state.armed = false
            state.expiresAt = nil
        end
        node._confirmButtonState = state
        return DrawWidgetSlots(imgui, node, node._confirmButtonSlots, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.inputText = {
    binds = { value = { storageType = "string" } },
    slots = { "label", "control" },
    validate = function(node, prefix)
        if node.maxLen ~= nil and (type(node.maxLen) ~= "number" or node.maxLen < 1) then
            libWarn("%s: inputText maxLen must be a positive number", prefix)
        end
        node._maxLen = math.floor(tonumber(node.maxLen) or 0)
        if node._maxLen < 1 then
            node._maxLen = nil
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
        local hasLabel = (node._label or "") ~= ""
        node._inputTextSlots = {
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
                    local ctx = node._inputTextCtx or {}
                    local maxLen = ctx.maxLen or node._maxLen or 256
                    local newValue, changed = imgui.InputText(node._imguiId, ctx.current or "", maxLen)
                    ShowPreparedTooltip(imgui, node)
                    if changed then
                        ctx.boundValue:set(newValue)
                        return true
                    end
                    return false
                end,
            },
        }
    end,
    validateGeometry = function(_, prefix, geometry)
        WarnIgnoredSlotKeys(prefix, geometry, "control", { "align" }, "inputText")
    end,
    draw = function(imgui, node, bound, width)
        local aliasNode = bound.value and bound.value.node or nil
        local ctx = node._inputTextCtx or {}
        ctx.boundValue = bound.value
        ctx.current = tostring(bound.value:get() or "")
        ctx.maxLen = node._maxLen or (aliasNode and aliasNode._maxLen) or 256
        node._inputTextCtx = ctx
        node._inputTextSlots[2].width = width
        return DrawWidgetSlots(imgui, node, node._inputTextSlots, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.dropdown = {
    binds = { value = { storageType = { "string", "int" } } },
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
                elseif type(value) ~= "string" and (type(value) ~= "number" or value ~= math.floor(value)) then
                    libWarn("%s: dropdown values must contain only strings or integers", prefix)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: dropdown displayValues must be a table", prefix)
        end
        ValidateValueColorsTable(node, prefix, "dropdown")
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
                    local previewColor = node._valueColors and node._valueColors[ctx.previewValue] or nil
                    local opened = DrawWithValueColor(imgui, previewColor, function()
                        return imgui.BeginCombo(node._imguiId, ChoiceDisplay(node, ctx.previewValue or ""))
                    end)
                    ShowPreparedTooltip(imgui, node)
                    if opened then
                        local changed = false
                        local pendingValue = nil
                          for index, candidate in ipairs(node.values or {}) do
                              local optionColor = node._valueColors and node._valueColors[candidate] or nil
                              local selected = DrawWithValueColor(imgui, optionColor, function()
                                  return imgui.Selectable(
                                      MakeSelectableId(ChoiceDisplay(node, candidate), index),
                                      false)
                              end)
                            if selected then
                                if candidate ~= ctx.current then
                                    pendingValue = candidate
                                end
                            end
                        end
                        imgui.EndCombo()
                        if pendingValue ~= nil then
                            ctx.boundValue:set(pendingValue)
                            changed = true
                        end
                        return changed
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

WidgetTypes.mappedDropdown = {
    binds = { value = {} },
    slots = { "label", "control" },
    validate = function(node, prefix)
        if type(node.getPreview) ~= "function" then
            libWarn("%s: mappedDropdown getPreview must be function", prefix)
        end
        if type(node.getOptions) ~= "function" then
            libWarn("%s: mappedDropdown getOptions must be function", prefix)
        end
        if node.getPreviewColor ~= nil and type(node.getPreviewColor) ~= "function" then
            libWarn("%s: mappedDropdown getPreviewColor must be function", prefix)
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
        local hasLabel = (node._label or "") ~= ""
        node._mappedDropdownSlots = {
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
                    local ctx = node._mappedDropdownCtx or {}
                    local opened = DrawWithValueColor(imgui, ctx.previewColor, function()
                        return imgui.BeginCombo(node._imguiId, ctx.preview or "")
                    end)
                    ShowPreparedTooltip(imgui, node)
                    if not opened then
                        return false
                    end

                    local changed = false
                    for _, option in ipairs(ctx.options or {}) do
                        local label
                        if type(option) == "table" then
                            label = tostring(option.label or option.value or "")
                        else
                            label = tostring(option or "")
                        end

                        local optionColor = type(option) == "table" and option.color or nil
                        local clicked = DrawWithValueColor(imgui, optionColor, function()
                            local uniqueId = type(option) == "table"
                                and (option.id or option.value or label)
                                or option
                            return imgui.Selectable(MakeSelectableId(label, uniqueId), false)
                        end)
                        if clicked then
                            if type(option) == "table" and type(option.onSelect) == "function" then
                                changed = option.onSelect(option, ctx.boundValue, ctx.uiState, node) == true or changed
                            else
                                local nextValue = type(option) == "table" and option.value or option
                                if nextValue ~= ctx.current then
                                    ctx.boundValue:set(nextValue)
                                    changed = true
                                end
                            end
                        end
                    end

                    imgui.EndCombo()
                    return changed
                end,
            },
        }
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredSlotKeys(prefix, geometry, "label", { "width", "align" }, "mappedDropdown")
    end,
    draw = function(imgui, node, bound, width, uiState)
        local ctx = node._mappedDropdownCtx or {}
        ctx.boundValue = bound.value
        ctx.current = bound.value and bound.value.get and bound.value:get() or nil
        ctx.uiState = uiState
        ctx.preview = type(node.getPreview) == "function"
            and tostring(node.getPreview(node, bound, uiState) or "")
            or ""
        ctx.previewColor = type(node.getPreviewColor) == "function"
            and node.getPreviewColor(node, bound, uiState)
            or nil
        ctx.options = type(node.getOptions) == "function"
            and node.getOptions(node, bound, uiState)
            or {}
        node._mappedDropdownCtx = ctx
        node._mappedDropdownSlots[2].width = width
        return DrawWidgetSlots(imgui, node, node._mappedDropdownSlots, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.packedDropdown = {
    binds = { value = { storageType = "int", rootType = "packedInt" } },
    slots = { "label", "control" },
    validate = function(node, prefix)
        PrepareWidgetText(node, node.binds and node.binds.value)
        ValidatePackedChoiceWidget(node, prefix, "packedDropdown")
        local hasLabel = (node._label or "") ~= ""
        node._packedDropdownSlots = {
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
                    local ctx = node._packedDropdownCtx or {}
                    local opened = DrawWithValueColor(imgui, ctx.previewColor, function()
                        return imgui.BeginCombo(node._imguiId, ctx.preview or "")
                    end)
                    ShowPreparedTooltip(imgui, node)
                    if not opened then
                        return false
                    end

                    local changed = false
                    local pendingClear = false
                    local pendingAlias = nil
                    if imgui.Selectable(MakeSelectableId(ctx.noneLabel or "None", "none"), false) then
                        pendingClear = true
                    end

                    for _, child in ipairs(ctx.children or {}) do
                        local optionColor = node._valueColors and node._valueColors[child.alias] or nil
                        local clicked = DrawWithValueColor(imgui, optionColor, function()
                            return imgui.Selectable(
                                MakeSelectableId(GetPackedChoiceLabel(node, child), child.alias),
                                false)
                        end)
                        if clicked then
                            pendingClear = false
                            pendingAlias = child.alias
                        end
                    end

                    imgui.EndCombo()
                    if pendingAlias ~= nil then
                        changed = ApplyPackedChoiceSelection(ctx.children, pendingAlias, ctx.selection) or changed
                    elseif pendingClear then
                        changed = ClearPackedChoiceSelection(ctx.children, ctx.selection) or changed
                    end
                    return changed
                end,
            },
        }
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredSlotKeys(prefix, geometry, "label", { "width", "align" }, "packedDropdown")
    end,
    draw = function(imgui, node, bound, width)
        local children = GetPackedChoiceChildren(node, bound, "packedDropdown")
        if not children then
            return false
        end

        local selection = ClassifyPackedChoice(node, children)
        local ctx = node._packedDropdownCtx or {}
        ctx.children = children
        ctx.selection = selection
        ctx.noneLabel = node.noneLabel or "None"
        ctx.multipleLabel = node.multipleLabel or "Multiple"
        if selection.state == "single" and selection.selectedChild then
            ctx.preview = GetPackedChoiceLabel(node, selection.selectedChild)
            ctx.previewColor = node._valueColors and node._valueColors[selection.selectedChild.alias] or nil
        elseif selection.state == "multiple" then
            ctx.preview = ctx.multipleLabel
            ctx.previewColor = nil
        else
            ctx.preview = ctx.noneLabel
            ctx.previewColor = nil
        end
        node._packedDropdownCtx = ctx
        node._packedDropdownSlots[2].width = width
        return DrawWidgetSlots(imgui, node, node._packedDropdownSlots, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.radio = {
    binds = { value = { storageType = { "string", "int" } } },
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
                elseif type(value) ~= "string" and (type(value) ~= "number" or value ~= math.floor(value)) then
                    libWarn("%s: radio values must contain only strings or integers", prefix)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: radio displayValues must be a table", prefix)
        end
        ValidateValueColorsTable(node, prefix, "radio")
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
                sameLine = true,
                draw = function(imgui)
                    local ctx = node._radioCtx or {}
                    local optionColor = node._valueColors and node._valueColors[candidate] or nil
                    local selected = DrawWithValueColor(imgui, optionColor, function()
                        return imgui.RadioButton(ChoiceDisplay(node, candidate), ctx.current == candidate)
                    end)
                    if selected then
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
        return DrawWidgetSlots(imgui, node, node._radioSlots, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.mappedRadio = {
    binds = { value = {} },
    slots = { "label" },
    validate = function(node, prefix)
        if type(node.getOptions) ~= "function" then
            libWarn("%s: mappedRadio getOptions must be function", prefix)
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
        node._mappedRadioSlots = {}
        local label = node._label or ""
        if label ~= "" then
            table.insert(node._mappedRadioSlots, {
                name = "label",
                draw = function(imgui)
                    imgui.Text(label)
                    ShowPreparedTooltip(imgui, node)
                    return false
                end,
            })
        end
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredSlotKeys(prefix, geometry, "label", { "width", "align" }, "mappedRadio")
    end,
    draw = function(imgui, node, bound, _, uiState)
        local ctx = node._mappedRadioCtx or {}
        ctx.boundValue = bound.value
        ctx.current = bound.value and bound.value.get and bound.value:get() or nil
        ctx.uiState = uiState
        ctx.options = type(node.getOptions) == "function"
            and node.getOptions(node, bound, uiState)
            or {}
        node._mappedRadioCtx = ctx

        local hasLabel = (node._label or "") ~= ""
        local slots = {}
        for _, slot in ipairs(node._mappedRadioSlots or {}) do
            slots[#slots + 1] = slot
        end
        for index, option in ipairs(ctx.options or {}) do
            slots[#slots + 1] = {
                name = "option:" .. tostring(index),
                sameLine = hasLabel or index > 1,
                draw = function()
                    local label
                    local selected
                    if type(option) == "table" then
                        label = tostring(option.label or option.value or "")
                        selected = option.selected == true
                    else
                        label = tostring(option or "")
                        selected = ctx.current ~= nil and option == ctx.current or false
                    end

                    if imgui.RadioButton(label, selected) then
                        if type(option) == "table" and type(option.onSelect) == "function" then
                            return option.onSelect(option, ctx.boundValue, ctx.uiState, node) == true
                        end

                        local nextValue = type(option) == "table" and option.value or option
                        if nextValue ~= ctx.current then
                            ctx.boundValue:set(nextValue)
                            ctx.current = nextValue
                            return true
                        end
                    end
                    return false
                end,
            }
        end

        return DrawWidgetSlots(imgui, node, slots, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.packedRadio = {
    binds = { value = { storageType = "int", rootType = "packedInt" } },
    slots = { "label" },
    validate = function(node, prefix)
        PrepareWidgetText(node, node.binds and node.binds.value)
        ValidatePackedChoiceWidget(node, prefix, "packedRadio")
        node._packedRadioSlots = {}
        local label = node._label or ""
        if label ~= "" then
            table.insert(node._packedRadioSlots, {
                name = "label",
                draw = function(imgui)
                    imgui.Text(label)
                    ShowPreparedTooltip(imgui, node)
                    return false
                end,
            })
        end
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredSlotKeys(prefix, geometry, "label", { "width", "align" }, "packedRadio")
    end,
    draw = function(imgui, node, bound)
        local children = GetPackedChoiceChildren(node, bound, "packedRadio")
        if not children then
            return false
        end

        local selection = ClassifyPackedChoice(node, children)
        local hasLabel = (node._label or "") ~= ""
        local slots = {}
        for _, slot in ipairs(node._packedRadioSlots or {}) do
            slots[#slots + 1] = slot
        end
        slots[#slots + 1] = {
            name = "option:none",
            sameLine = hasLabel,
            draw = function(_imgui)
                if _imgui.RadioButton(node.noneLabel or "None", selection.state == "none") then
                    return ClearPackedChoiceSelection(children, selection) == true
                end
                return false
            end,
        }
        for index, child in ipairs(children) do
            slots[#slots + 1] = {
                name = "option:" .. tostring(index),
                sameLine = true,
                draw = function(_imgui)
                    local optionColor = node._valueColors and node._valueColors[child.alias] or nil
                    local clicked = DrawWithValueColor(_imgui, optionColor, function()
                        return _imgui.RadioButton(
                            GetPackedChoiceLabel(node, child),
                            selection.selectedChild and selection.selectedChild.alias == child.alias or false)
                    end)
                    if clicked then
                        return ApplyPackedChoiceSelection(children, child.alias, selection) == true
                    end
                    return false
                end,
            }
        end

        return DrawWidgetSlots(imgui, node, slots, GetCursorPosXSafe(imgui))
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
    if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
        libWarn("%s: stepper displayValues must be a table", prefix)
    end
    ValidateValueColorsTable(node, prefix, "stepper")
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
    binds = {
        value = { storageType = "int", rootType = "packedInt" },
        filterText = { storageType = "string", optional = true },
        filterMode = { storageType = "string", optional = true },
    },
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

        ValidateValueColorsTable(node, prefix, "packedCheckboxList")

        -- packedCheckboxList renders items directly in draw(), but it still needs
        -- stable per-item slot descriptors so static geometry can target
        -- item:N consistently without rebuilding slot metadata every frame.
        node._packedSlots = BuildIndexedSlots(node.slotCount, function(index)
            return {
                name = "item:" .. tostring(index),
                line = index,
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
            return false
        end

        local changed = false
        local filterBind = bound.filterText
        local filterText = filterBind and filterBind.get() or ""
        if type(filterText) ~= "string" then filterText = "" end
        local lowerFilter = filterText:lower()
        local hasFilter = lowerFilter ~= ""
        local filterModeBind = bound.filterMode
        local filterMode = filterModeBind and filterModeBind.get() or "all"
        if filterMode ~= "checked" and filterMode ~= "unchecked" then
            filterMode = "all"
        end
        local rowStart = GetCursorPosXSafe(imgui)
        local currentLine = nil
        local visibleIndex = 0

        for _, child in ipairs(children) do
            if child ~= nil then
                local label = child.label or ""
                local val = child.get()
                if val == nil then val = false end
                local matchesText = not hasFilter or label:lower():find(lowerFilter, 1, true) ~= nil
                local matchesMode = filterMode == "all"
                    or (filterMode == "checked" and val == true)
                    or (filterMode == "unchecked" and val ~= true)
                local visible = matchesText and matchesMode
                if visible and visibleIndex < node.slotCount then
                    visibleIndex = visibleIndex + 1
                    local slot = node._packedSlots[visibleIndex]
                    local slotName = slot.name
                    local geometry = GetSlotGeometry(node, slotName)
                    local line = (geometry and geometry.line) or slot.line or 1
                    local start = (geometry and geometry.start) or slot.start
                    if currentLine ~= line then
                        currentLine = line
                    elseif slot.sameLine ~= false then
                        imgui.SameLine()
                    end

                    if type(start) == "number" then
                        imgui.SetCursorPosX(rowStart + start)
                    end

                    imgui.PushID((slotName or "item") .. "_" .. tostring(visibleIndex))
                    local color = node._valueColors and node._valueColors[child.alias] or nil
                    local newVal, childChanged = DrawWithValueColor(imgui, color, function()
                        return imgui.Checkbox(label, val == true)
                    end)
                    if childChanged then
                        child.set(newVal)
                        changed = true
                    end
                    imgui.PopID()
                end
            end
        end

        return changed
    end,
}
