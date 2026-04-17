local internal = AdamantModpackLib_Internal
local libWarn = internal.logging.warnIf
local widgetHelpers = {}

---@alias Color number[]
---@alias ChoiceValue any
---@alias ChoiceDisplayValues table<any, string>
---@alias ValueColorMap table<any, Color>
---@alias PackedSelectionMode "singleEnabled"|"singleRemaining"

function widgetHelpers.NormalizeColor(value)
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

function widgetHelpers.NormalizeChoiceValue(node, value)
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

function widgetHelpers.ChoiceDisplay(node, value)
    if node.displayValues and node.displayValues[value] ~= nil then
        return tostring(node.displayValues[value])
    end
    return tostring(value)
end

function widgetHelpers.ValidateValueColorsTable(node, prefix, widgetName)
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
        local normalized = widgetHelpers.NormalizeColor(color)
        if normalized == nil then
            libWarn("%s: %s valueColors[%s] must be a 3- or 4-number color table", prefix, widgetName, tostring(key))
        else
            normalizedColors[key] = normalized
        end
    end
    node._valueColors = normalizedColors
end

function widgetHelpers.DrawWithValueColor(imgui, color, drawFn)
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

function widgetHelpers.MakeSelectableId(label, uniqueId)
    return tostring(label or "") .. "##" .. tostring(uniqueId or "")
end

function widgetHelpers.ValidateDisplayValuesTable(node, prefix, widgetName)
    if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
        libWarn("%s: %s displayValues must be a table", prefix, widgetName)
    end
end

function widgetHelpers.GetPackedChoiceMode(node)
    local mode = node.selectionMode
    if mode == nil or mode == "" then
        return "singleEnabled"
    end
    return mode
end

function widgetHelpers.GetPackedChoiceChildren(node, bound, widgetName)
    local children = bound and bound.value and bound.value.children or nil
    if type(children) ~= "table" then
        libWarn("%s: no packed children for alias '%s'; bind to a packedInt root",
            widgetName, tostring(node.binds and node.binds.value))
        return nil
    end
    return children
end

function widgetHelpers.GetPackedChoiceLabel(node, child)
    if type(node.displayValues) == "table" and node.displayValues[child.alias] ~= nil then
        return tostring(node.displayValues[child.alias])
    end
    return tostring(child.label or child.alias or "")
end

function widgetHelpers.GetPackedChoiceNoneValue(mode)
    if mode == "singleRemaining" then
        return false
    end
    return false
end

function widgetHelpers.IsPackedChoiceActive(mode, value)
    if mode == "singleRemaining" then
        return value == false
    end
    return value == true
end

function widgetHelpers.GetPackedChoiceWriteValue(mode, isActive)
    if mode == "singleRemaining" then
        if isActive then
            return false
        end
        return true
    end
    return isActive == true
end

function widgetHelpers.ClassifyPackedChoice(node, children)
    local mode = widgetHelpers.GetPackedChoiceMode(node)
    local noneValue = widgetHelpers.GetPackedChoiceNoneValue(mode)
    local activeCount = 0
    local totalCount = 0
    local lastActiveChild = nil

    for _, child in ipairs(children or {}) do
        totalCount = totalCount + 1
        local value = child.get and child.get() or noneValue
        if value == nil then
            value = noneValue
        end
        if widgetHelpers.IsPackedChoiceActive(mode, value) then
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

function widgetHelpers.ApplyPackedChoiceSelection(children, selectedAlias, selection)
    local changed = false
    for _, child in ipairs(children or {}) do
        local shouldBeActive = child.alias == selectedAlias
        local nextValue = widgetHelpers.GetPackedChoiceWriteValue(selection.mode, shouldBeActive)
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

function widgetHelpers.ClearPackedChoiceSelection(children, selection)
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

function widgetHelpers.ValidatePackedChoiceWidget(node, prefix, widgetName)
    local mode = widgetHelpers.GetPackedChoiceMode(node)
    if mode ~= "singleEnabled" and mode ~= "singleRemaining" then
        libWarn("%s: %s selectionMode must be 'singleEnabled' or 'singleRemaining'", prefix, widgetName)
    end
    if node.noneLabel ~= nil and type(node.noneLabel) ~= "string" then
        libWarn("%s: %s noneLabel must be a string", prefix, widgetName)
    end
    if node.multipleLabel ~= nil and type(node.multipleLabel) ~= "string" then
        libWarn("%s: %s multipleLabel must be a string", prefix, widgetName)
    end
    widgetHelpers.ValidateDisplayValuesTable(node, prefix, widgetName)
    widgetHelpers.ValidateValueColorsTable(node, prefix, widgetName)
end

internal.widgetHelpers = widgetHelpers
