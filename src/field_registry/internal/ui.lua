local internal = AdamantModpackLib_Internal
local ui = internal.ui
local widgets = internal.widgets

local function KeyStr(key)
    if type(key) == "table" then
        return table.concat(key, ".")
    end
    return tostring(key)
end

ui.StorageKey = KeyStr

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

ui.NormalizeInteger = NormalizeInteger

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

ui.NormalizeChoiceValue = NormalizeChoiceValue

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

ui.NormalizeColor = NormalizeColor

local function GetCursorPosXSafe(imgui)
    return imgui.GetCursorPosX() or 0
end

ui.GetCursorPosXSafe = GetCursorPosXSafe

local function GetCursorPosYSafe(imgui)
    local value = imgui.GetCursorPosY()
    if type(value) == "number" then
        return value
    end
    return 0
end

ui.GetCursorPosYSafe = GetCursorPosYSafe

local function SetCursorPosSafe(imgui, x, y)
    if type(imgui.SetCursorPos) == "function" then
        imgui.SetCursorPos(x, y)
    end
    if type(imgui.SetCursorPosX) == "function" and type(x) == "number" then
        imgui.SetCursorPosX(x)
    end
    if type(imgui.SetCursorPosY) == "function" and type(y) == "number" then
        imgui.SetCursorPosY(y)
    end
end

ui.SetCursorPosSafe = SetCursorPosSafe

local function GetStyleMetricX(style, key, fallback)
    local metric = style and style[key]
    if type(metric) == "table" and type(metric.x) == "number" then
        return metric.x
    end
    return fallback
end

ui.GetStyleMetricX = GetStyleMetricX

local function GetStyleMetricY(style, key, fallback)
    local metric = style and style[key]
    if type(metric) == "table" and type(metric.y) == "number" then
        return metric.y
    end
    return fallback
end

ui.GetStyleMetricY = GetStyleMetricY

local function CalcTextWidth(imgui, text)
    local width = imgui.CalcTextSize(tostring(text or ""))
    if type(width) == "number" then
        return width
    end
    if type(width) == "table" then
        if type(width.x) == "number" then
            return width.x
        end
        if type(width[1]) == "number" then
            return width[1]
        end
    end
    return 0
end

ui.CalcTextWidth = CalcTextWidth

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

ui.EstimateStructuredRowAdvanceY = EstimateStructuredRowAdvanceY
widgets.estimateRowAdvanceY = EstimateStructuredRowAdvanceY

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

ui.DrawStructuredAt = DrawStructuredAt
widgets.drawStructuredAt = DrawStructuredAt

local function ShowPreparedTooltip(imgui, node)
    if node and node._hasTooltip == true and imgui.IsItemHovered() then
        imgui.SetTooltip(node._tooltipText)
    end
end

ui.ShowPreparedTooltip = ShowPreparedTooltip

local function EstimateButtonWidth(imgui, label)
    local style = imgui.GetStyle()
    local framePaddingX = GetStyleMetricX(style, "FramePadding", 0)
    return CalcTextWidth(imgui, label) + framePaddingX * 2
end

ui.EstimateButtonWidth = EstimateButtonWidth

local function EstimateToggleWidth(imgui, label)
    local frameHeight = type(imgui.GetFrameHeight) == "function" and imgui.GetFrameHeight() or nil
    if type(frameHeight) ~= "number" or frameHeight <= 0 then
        frameHeight = EstimateStructuredRowAdvanceY(imgui)
    end
    local style = type(imgui.GetStyle) == "function" and imgui.GetStyle() or nil
    local itemInnerSpacingX = GetStyleMetricX(style, "ItemInnerSpacing", 4)
    return frameHeight + itemInnerSpacingX + CalcTextWidth(imgui, label)
end

ui.EstimateToggleWidth = EstimateToggleWidth

local function DrawOrderedEntries(imgui, entries, startX, startY, fallbackHeight)
    local style = type(imgui.GetStyle) == "function" and imgui.GetStyle() or nil
    local itemSpacingX = GetStyleMetricX(style, "ItemSpacing", 8)
    local currentLine = nil
    local currentRowY = startY
    local currentRowAdvance = fallbackHeight
    local currentX = startX
    local maxRight = startX
    local maxBottom = startY
    local changed = false

    for _, entry in ipairs(entries or {}) do
        local isNewLine = currentLine ~= entry.line
        if isNewLine then
            if currentLine ~= nil then
                currentRowY = currentRowY + currentRowAdvance
            end
            currentLine = entry.line
            currentRowAdvance = fallbackHeight
            currentX = startX
        end

        local slotX
        if type(entry.start) == "number" then
            slotX = startX + entry.start
        else
            slotX = currentX
        end

        local estimatedWidth = type(entry.estimateWidth) == "function"
            and entry.estimateWidth(imgui, entry)
            or 0
        local drawX = slotX
        if type(entry.width) == "number" and type(estimatedWidth) == "number" then
            local offset = 0
            if entry.align == "center" then
                offset = math.max((entry.width - estimatedWidth) / 2, 0)
            elseif entry.align == "right" then
                offset = math.max(entry.width - estimatedWidth, 0)
            end
            drawX = slotX + offset
        end

        local measuredWidth = estimatedWidth
        local measuredHeight = fallbackHeight
        local entryChanged, _, _, consumedHeight = DrawStructuredAt(
            imgui,
            slotX,
            currentRowY,
            fallbackHeight,
            function()
                if drawX ~= slotX then
                    if type(imgui.SetCursorPosX) == "function" then
                        imgui.SetCursorPosX(drawX)
                    else
                        SetCursorPosSafe(imgui, drawX, currentRowY)
                    end
                end
                local widgetChanged, contentWidth, contentHeight = entry.render(imgui, entry)
                if type(contentWidth) == "number" and contentWidth > 0 then
                    measuredWidth = contentWidth
                end
                if type(contentHeight) == "number" and contentHeight > 0 then
                    measuredHeight = contentHeight
                end
                return widgetChanged == true
            end)
        if entryChanged then
            changed = true
        end

        local slotConsumedHeight = measuredHeight > 0 and measuredHeight or consumedHeight
        if slotConsumedHeight > currentRowAdvance then
            currentRowAdvance = slotConsumedHeight
        end

        local slotConsumedWidth = type(entry.width) == "number" and entry.width or measuredWidth or 0
        local slotRight = slotX + math.max(slotConsumedWidth, 0)
        if slotRight > maxRight then
            maxRight = slotRight
        end
        local slotBottom = currentRowY + math.max(slotConsumedHeight or 0, 0)
        if slotBottom > maxBottom then
            maxBottom = slotBottom
        end

        currentX = math.max(currentX, slotRight + itemSpacingX)
    end

    return math.max(maxRight - startX, 0), math.max(maxBottom - startY, 0), changed
end

ui.DrawOrderedEntries = DrawOrderedEntries
