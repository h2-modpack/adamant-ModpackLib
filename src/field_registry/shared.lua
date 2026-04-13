local internal = AdamantModpackLib_Internal
local shared = internal.shared
local StorageTypes = shared.StorageTypes
local WidgetTypes = shared.WidgetTypes
local LayoutTypes = shared.LayoutTypes
local libWarn = shared.libWarn
local registry = shared.fieldRegistry or {}
shared.fieldRegistry = registry
local mergedCustomTypesCache = setmetatable({}, { __mode = "k" })

local REQUIRED_STORAGE_METHODS = { "validate", "normalize", "toHash", "fromHash" }
local REQUIRED_LAYOUT_METHODS  = { "validate", "render" }

local function KeyStr(key)
    if type(key) == "table" then
        return table.concat(key, ".")
    end
    return tostring(key)
end

shared.StorageKey = KeyStr

local function NormalizeInteger(node, value)
    local num = tonumber(value)
    if num == nil then
        num = tonumber(node.default) or 0
    end
    num = math.floor(num)
    if node.min ~= nil and num < node.min then num = node.min end
    if node.max ~= nil and num > node.max then num = node.max end
    return num
end

shared.NormalizeInteger = NormalizeInteger
registry.NormalizeInteger = NormalizeInteger

local function NormalizeChoiceValue(node, value)
    local values = node.values
    if type(values) ~= "table" or #values == 0 then
        return value ~= nil and value or node.default
    end

    if value ~= nil then
        for _, candidate in ipairs(values) do
            if candidate == value then
                return candidate
            end
        end
    end

    if node.default ~= nil then
        for _, candidate in ipairs(values) do
            if candidate == node.default then
                return candidate
            end
        end
    end

    return values[1]
end

registry.NormalizeChoiceValue = NormalizeChoiceValue

local function NormalizeColor(value)
    if type(value) ~= "table" then
        return nil
    end
    local r = tonumber(value[1])
    local g = tonumber(value[2])
    local b = tonumber(value[3])
    local a = value[4] ~= nil and tonumber(value[4]) or 1
    if r == nil or g == nil or b == nil or a == nil then
        return nil
    end
    return { r, g, b, a }
end

shared.NormalizeColor = NormalizeColor
registry.NormalizeColor = NormalizeColor

local function PrepareWidgetText(node, fallbackLabel)
    if type(node) ~= "table" then
        return
    end
    node._label = tostring(node.label or fallbackLabel or "")
    node._tooltipText = node.tooltip ~= nil and tostring(node.tooltip) or ""
    node._hasTooltip = node._tooltipText ~= ""
end

shared.PrepareWidgetText = PrepareWidgetText
registry.PrepareWidgetText = PrepareWidgetText

local function ChoiceDisplay(node, value)
    if node.displayValues and node.displayValues[value] ~= nil then
        return tostring(node.displayValues[value])
    end
    return tostring(value)
end

shared.ChoiceDisplay = ChoiceDisplay
registry.ChoiceDisplay = ChoiceDisplay

local function GetCursorPosXSafe(imgui)
    return imgui.GetCursorPosX() or 0
end

registry.GetCursorPosXSafe = GetCursorPosXSafe

local function GetCursorPosYSafe(imgui)
    local value = imgui.GetCursorPosY()
    if type(value) == "number" then
        return value
    end
    return 0
end

registry.GetCursorPosYSafe = GetCursorPosYSafe

local function SetCursorPosSafe(imgui, x, y)
    imgui.SetCursorPos(x, y)
end

registry.SetCursorPosSafe = SetCursorPosSafe

local function BuildSlotSet(widgetType)
    if type(widgetType) ~= "table" or type(widgetType.slots) ~= "table" then
        return {}
    end
    local allowed = {}
    for _, key in ipairs(widgetType.slots) do
        allowed[key] = true
    end
    return allowed
end

local function ValidateDynamicSlot(widgetType, node, slotName)
    if type(widgetType) ~= "table" then
        return false, nil
    end
    local dynamicSlots = widgetType.dynamicSlots
    if type(dynamicSlots) == "function" then
        local ok, err = dynamicSlots(node, slotName)
        return ok == true, err
    end
    return false, nil
end

local function ParseWidgetGeometry(node, prefix, widgetType, geometry)
    if geometry == nil then
        return {}
    end
    if type(geometry) ~= "table" then
        libWarn("%s: geometry must be a table", prefix)
        return {}
    end
    local allowed = BuildSlotSet(widgetType)
    local slotSpecs = geometry.slots
    local parsed = {}

    for key in pairs(geometry) do
        if key ~= "slots" then
            libWarn("%s: geometry key '%s' is not supported; geometry only supports 'slots'",
                prefix, tostring(key))
        end
    end

    if slotSpecs == nil then
        return parsed
    end
    if type(slotSpecs) ~= "table" then
        libWarn("%s: geometry.slots must be a list", prefix)
        return parsed
    end

    local seen = {}
    for index, slotSpec in ipairs(slotSpecs) do
        local slotPrefix = ("%s geometry.slots[%d]"):format(prefix, index)
        if type(slotSpec) ~= "table" then
            libWarn("%s must be a table", slotPrefix)
        else
            local slotName = slotSpec.name
            if type(slotName) ~= "string" or slotName == "" then
                libWarn("%s.name must be a non-empty string", slotPrefix)
            else
                local dynamicOk, dynamicErr = ValidateDynamicSlot(widgetType, node, slotName)
                if dynamicErr ~= nil then
                    libWarn("%s: %s", prefix, tostring(dynamicErr))
                elseif not allowed[slotName] and not dynamicOk then
                    libWarn("%s: geometry slot '%s' is not supported by widget type '%s'",
                        prefix, tostring(slotName), tostring(node.type))
                end
                if seen[slotName] then
                    libWarn("%s: geometry slot '%s' is declared more than once", prefix, tostring(slotName))
                end
                seen[slotName] = true

                for key, value in pairs(slotSpec) do
                    if key ~= "name" and key ~= "line" and key ~= "start" and key ~= "width" and key ~= "align" then
                        libWarn("%s: unknown slot geometry key '%s'", slotPrefix, tostring(key))
                    elseif key == "line" then
                        if type(value) ~= "number" then
                            libWarn("%s.line must be a number", slotPrefix)
                        elseif value < 1 or math.floor(value) ~= value then
                            libWarn("%s.line must be a positive integer", slotPrefix)
                        end
                    elseif key == "start" then
                        if type(value) ~= "number" then
                            libWarn("%s.start must be a number", slotPrefix)
                        elseif value < 0 then
                            libWarn("%s.start must be a non-negative number", slotPrefix)
                        end
                    elseif key == "width" then
                        if type(value) ~= "number" or value <= 0 then
                            libWarn("%s.width must be a positive number", slotPrefix)
                        end
                    elseif key == "align" then
                        if value ~= "center" and value ~= "right" then
                            libWarn("%s.align must be one of 'center' or 'right'", slotPrefix)
                        end
                    end
                end

                if slotSpec.align ~= nil and (type(slotSpec.width) ~= "number" or slotSpec.width <= 0) then
                    libWarn("%s.align requires width on the same slot", slotPrefix)
                end

                parsed[slotName] = {
                    line = type(slotSpec.line) == "number" and slotSpec.line >= 1 and math.floor(slotSpec.line) == slotSpec.line
                        and slotSpec.line or nil,
                    start = type(slotSpec.start) == "number" and slotSpec.start or nil,
                    width = type(slotSpec.width) == "number" and slotSpec.width > 0 and slotSpec.width or nil,
                    align = (slotSpec.align == "center" or slotSpec.align == "right") and slotSpec.align or nil,
                }
            end
        end
    end
    return parsed
end

local function ValidateWidgetGeometry(node, prefix, widgetType)
    node._defaultSlotGeometry = ParseWidgetGeometry(
        node,
        prefix .. " defaultGeometry",
        widgetType,
        type(widgetType) == "table" and widgetType.defaultGeometry or nil)
    node._slotGeometry = ParseWidgetGeometry(node, prefix, widgetType, node.geometry)
    if type(widgetType) == "table" and type(widgetType.validateGeometry) == "function" then
        widgetType.validateGeometry(node, prefix .. " defaultGeometry", node._defaultSlotGeometry)
        widgetType.validateGeometry(node, prefix, node._slotGeometry)
    end
end

registry.ValidateWidgetGeometry = ValidateWidgetGeometry

local function GetSlotGeometry(node, slotName)
    if type(node) ~= "table" then
        return nil
    end
    local defaultSlot = type(node._defaultSlotGeometry) == "table" and node._defaultSlotGeometry[slotName] or nil
    local staticSlot = type(node._slotGeometry) == "table" and node._slotGeometry[slotName] or nil

    if type(defaultSlot) ~= "table" then
        return staticSlot
    end
    if type(staticSlot) ~= "table" then
        return defaultSlot
    end

    local merged = {}
    for key, value in pairs(defaultSlot) do
        merged[key] = value
    end
    for key, value in pairs(staticSlot) do
        merged[key] = value
    end
    if next(merged) == nil then
        return nil
    end
    return merged
end

registry.GetSlotGeometry = GetSlotGeometry

local function GetStyleMetricX(style, key, fallback)
    local metric = style and style[key]
    if type(metric) == "table" and type(metric.x) == "number" then
        return metric.x
    end
    return fallback
end

registry.GetStyleMetricX = GetStyleMetricX

local function GetStyleMetricY(style, key, fallback)
    local metric = style and style[key]
    if type(metric) == "table" and type(metric.y) == "number" then
        return metric.y
    end
    return fallback
end

registry.GetStyleMetricY = GetStyleMetricY

local function CalcTextWidth(imgui, text)
    local width = imgui.CalcTextSize(tostring(text or ""))
    return type(width) == "number" and width or 0
end

registry.CalcTextWidth = CalcTextWidth

local function EstimateStructuredRowAdvanceY(imgui)
    local value = imgui.GetFrameHeightWithSpacing()
    if type(value) == "number" and value > 0 then
        return value
    end
    value = imgui.GetTextLineHeightWithSpacing()
    if type(value) == "number" and value > 0 then
        return value
    end
    local style = imgui.GetStyle()
    local framePaddingY = type(style) == "table" and GetStyleMetricY(style, "FramePadding", 3) or 3
    local itemSpacingY = type(style) == "table" and GetStyleMetricY(style, "ItemSpacing", 4) or 4
    return 16 + framePaddingY * 2 + itemSpacingY
end

registry.EstimateStructuredRowAdvanceY = EstimateStructuredRowAdvanceY

local function DrawStructuredAt(imgui, startX, startY, fallbackHeight, drawFn)
    SetCursorPosSafe(imgui, startX, startY)
    local changed = drawFn() == true
    local endX = GetCursorPosXSafe(imgui)
    local endY = GetCursorPosYSafe(imgui)
    local consumedHeight = endY - startY
    if type(consumedHeight) ~= "number" or consumedHeight <= 0 then
        consumedHeight = fallbackHeight
    end
    return changed, endX, endY, consumedHeight
end

registry.DrawStructuredAt = DrawStructuredAt

local function ShowPreparedTooltip(imgui, node)
    if node and node._hasTooltip == true and imgui.IsItemHovered() then
        imgui.SetTooltip(node._tooltipText)
    end
end

registry.ShowPreparedTooltip = ShowPreparedTooltip

local function EstimateButtonWidth(imgui, label)
    local style = imgui.GetStyle()
    local framePaddingX = GetStyleMetricX(style, "FramePadding", 0)
    return CalcTextWidth(imgui, label) + framePaddingX * 2
end

registry.EstimateButtonWidth = EstimateButtonWidth

local function AlignSlotContent(imgui, slot, contentWidth)
    if type(slot) ~= "table" or slot.width == nil or slot.align == nil then
        return
    end
    if type(contentWidth) ~= "number" then
        return
    end
    local slotStart = imgui.GetCursorPosX()
    local alignOffset = slot.align == "center"
        and math.max((slot.width - contentWidth) / 2, 0)
        or math.max(slot.width - contentWidth, 0)
    imgui.SetCursorPosX(slotStart + alignOffset)
end

registry.AlignSlotContent = AlignSlotContent

local function BuildSlotOrderKey(entries)
    local parts = {}
    for _, entry in ipairs(entries) do
        parts[#parts + 1] = tostring(entry.slot.name or "")
        parts[#parts + 1] = "@"
        parts[#parts + 1] = tostring(entry.index)
        parts[#parts + 1] = ":"
        parts[#parts + 1] = tostring(entry.line or 1)
        parts[#parts + 1] = ":"
        parts[#parts + 1] = entry.start ~= nil and tostring(entry.start) or "_"
        parts[#parts + 1] = "|"
    end
    return table.concat(parts)
end

local function GetOrderedSlotPositions(node, entries)
    local orderKey = BuildSlotOrderKey(entries)
    if type(node) == "table" and node._slotOrderCacheKey == orderKey
        and type(node._slotOrderCacheOrder) == "table" then
        return node._slotOrderCacheOrder
    end

    local orderedPositions = {}
    for index = 1, #entries do
        orderedPositions[index] = index
    end

    table.sort(orderedPositions, function(leftIndex, rightIndex)
        local left = entries[leftIndex]
        local right = entries[rightIndex]
        if left.line ~= right.line then
            return left.line < right.line
        end
        if type(left.start) == "number" and type(right.start) == "number" and left.start ~= right.start then
            return left.start < right.start
        end
        return left.index < right.index
    end)

    if type(node) == "table" then
        node._slotOrderCacheKey = orderKey
        node._slotOrderCacheOrder = orderedPositions
    end
    return orderedPositions
end

local function DrawWidgetSlots(imgui, node, slots, rowStart)
    if type(slots) ~= "table" then
        return false
    end

    local changed = false
    rowStart = rowStart or GetCursorPosXSafe(imgui)
    local rowStartY = GetCursorPosYSafe(imgui)
    local defaultRowAdvance = EstimateStructuredRowAdvanceY(imgui)
    local renderSlots = type(node) == "table" and node._renderSlotCache or nil
    if type(renderSlots) ~= "table" then
        renderSlots = {}
        if type(node) == "table" then
            node._renderSlotCache = renderSlots
        end
    end
    local renderCount = 0

    for index, slot in ipairs(slots) do
        if type(slot) == "table" and type(slot.draw) == "function" then
            renderCount = renderCount + 1
            local entry = renderSlots[renderCount]
            if type(entry) ~= "table" then
                entry = {}
                renderSlots[renderCount] = entry
            end
            local geometry = type(slot.name) == "string" and GetSlotGeometry(node, slot.name) or nil
            entry.slot = slot
            entry.index = index
            entry.hidden = slot.hidden == true
            entry.line = (geometry and geometry.line) or slot.line or 1
            entry.start = (geometry and geometry.start) or slot.start
            entry.width = (geometry and geometry.width) or slot.width
            entry.align = (geometry and geometry.align) or slot.align
        end
    end
    for index = renderCount + 1, #renderSlots do
        renderSlots[index] = nil
    end

    local orderedPositions = GetOrderedSlotPositions(node, renderSlots)

    local currentLine = nil
    local currentRowY = rowStartY
    local currentRowAdvance = defaultRowAdvance

    for _, position in ipairs(orderedPositions) do
        local entry = renderSlots[position]
        if not entry.hidden then
            local slot = entry.slot
            local merged = entry.merged
            if type(merged) ~= "table" then
                merged = {}
                entry.merged = merged
            end
            merged.name = slot.name
            merged.start = entry.start
            merged.width = entry.width
            merged.align = entry.align
            merged.sameLine = slot.sameLine
            merged.line = entry.line

            if currentLine ~= entry.line then
                if currentLine ~= nil then
                    currentRowY = currentRowY + currentRowAdvance
                end
                currentLine = entry.line
                currentRowAdvance = defaultRowAdvance
            elseif slot.sameLine ~= false and type(entry.start) ~= "number" then
                imgui.SameLine()
            end

            local slotX = type(entry.start) == "number" and (rowStart + entry.start) or GetCursorPosXSafe(imgui)
            if type(entry.start) == "number" then
                merged.start = entry.start
            end
            local slotChanged, nextX, _, consumedAdvance = DrawStructuredAt(
                imgui,
                slotX,
                currentRowY,
                defaultRowAdvance,
                function()
                    if type(entry.width) == "number" and entry.width > 0 then
                        imgui.PushItemWidth(entry.width)
                    end
                    imgui.PushID((slot.name or "slot") .. "_" .. tostring(entry.index))
                    local drewChanged = slot.draw(imgui, merged, rowStart) == true
                    imgui.PopID()
                    if type(entry.width) == "number" and entry.width > 0 then
                        imgui.PopItemWidth()
                    end
                    return drewChanged
                end)
            if slotChanged then
                changed = true
            end
            if consumedAdvance > currentRowAdvance then
                currentRowAdvance = consumedAdvance
            end

            SetCursorPosSafe(imgui, nextX, currentRowY)
        end
    end

    SetCursorPosSafe(imgui, rowStart, currentRowY + currentRowAdvance)
    return changed
end

registry.DrawWidgetSlots = DrawWidgetSlots

local function AssertRegistryContracts(registryTable, required, label)
    for typeName, item in pairs(registryTable) do
        if type(item) ~= "table" then
            error(("%s type '%s' must be a table"):format(label, tostring(typeName)), 0)
        end
        for _, method in ipairs(required) do
            if type(item[method]) ~= "function" then
                error(("%s type '%s' is missing required method '%s'"):format(
                    label, tostring(typeName), method), 0)
            end
        end
    end
end

local function AssertWidgetContracts(registryTable, label)
    for typeName, item in pairs(registryTable) do
        if type(item) ~= "table" then
            error(("%s type '%s' must be a table"):format(label, tostring(typeName)), 0)
        end
        if type(item.validate) ~= "function" then
            error(("%s type '%s' is missing required method 'validate'"):format(
                label, tostring(typeName)), 0)
        end
        if type(item.draw) ~= "function" then
            error(("%s type '%s' is missing required method 'draw'"):format(
                label, tostring(typeName)), 0)
        end
    end
end

local function AssertWidgetSlotsContract(widgetType, typeName, label)
    if widgetType.slots == nil then
        return
    end
    if type(widgetType.slots) ~= "table" then
        error(("%s type '%s' slots must be a list of non-empty strings"):format(
            label, tostring(typeName)), 0)
    end
    for index, key in ipairs(widgetType.slots) do
        if type(key) ~= "string" or key == "" then
            error(("%s type '%s' slots[%d] must be a non-empty string"):format(
                label, tostring(typeName), index), 0)
        end
    end
end

local function ValidateCustomTypes(customTypes, label)
    if type(customTypes) ~= "table" then
        error((label or "module") .. ": definition.customTypes must be a table", 0)
    end
    local widgets = customTypes.widgets
    local layouts = customTypes.layouts
    if widgets ~= nil then
        if type(widgets) ~= "table" then
            error((label or "module") .. ": customTypes.widgets must be a table", 0)
        end
        for typeName, item in pairs(widgets) do
            if WidgetTypes[typeName] then
                error(("%s: customTypes.widgets '%s' collides with built-in widget type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            if LayoutTypes[typeName] then
                error(("%s: customTypes.widgets '%s' collides with built-in layout type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            AssertWidgetContracts({ [typeName] = item }, "Widget")
            if type(item) == "table" and type(item.binds) ~= "table" then
                error(("%s: customTypes.widgets '%s' must declare a binds table"):format(
                    label or "module", tostring(typeName)), 0)
            end
            AssertWidgetSlotsContract(item, typeName, "Widget")
        end
    end
    if layouts ~= nil then
        if type(layouts) ~= "table" then
            error((label or "module") .. ": customTypes.layouts must be a table", 0)
        end
        for typeName, item in pairs(layouts) do
            if WidgetTypes[typeName] then
                error(("%s: customTypes.layouts '%s' collides with built-in widget type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            if LayoutTypes[typeName] then
                error(("%s: customTypes.layouts '%s' collides with built-in layout type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            AssertRegistryContracts({ [typeName] = item }, REQUIRED_LAYOUT_METHODS, "Layout")
        end
    end
end

registry.ValidateCustomTypes = ValidateCustomTypes

local function MergeCustomTypes(customTypes)
    if not customTypes then
        return WidgetTypes, LayoutTypes
    end
    local cached = mergedCustomTypesCache[customTypes]
    if cached then
        return cached.widgets, cached.layouts
    end
    local mergedWidgets = {}
    for k, v in pairs(WidgetTypes) do mergedWidgets[k] = v end
    if type(customTypes.widgets) == "table" then
        for k, v in pairs(customTypes.widgets) do mergedWidgets[k] = v end
    end
    local mergedLayouts = {}
    for k, v in pairs(LayoutTypes) do mergedLayouts[k] = v end
    if type(customTypes.layouts) == "table" then
        for k, v in pairs(customTypes.layouts) do mergedLayouts[k] = v end
    end
    mergedCustomTypesCache[customTypes] = {
        widgets = mergedWidgets,
        layouts = mergedLayouts,
    }
    return mergedWidgets, mergedLayouts
end

registry.MergeCustomTypes = MergeCustomTypes

function public.validateRegistries()
    AssertRegistryContracts(StorageTypes, REQUIRED_STORAGE_METHODS, "Storage")
    AssertWidgetContracts(WidgetTypes, "Widget")
    AssertRegistryContracts(LayoutTypes, REQUIRED_LAYOUT_METHODS, "Layout")
    for typeName, widgetType in pairs(WidgetTypes) do
        if type(widgetType.binds) ~= "table" then
            error(("Widget type '%s' must declare a binds table"):format(tostring(typeName)), 0)
        end
        AssertWidgetSlotsContract(widgetType, typeName, "Widget")
    end
    return true
end
