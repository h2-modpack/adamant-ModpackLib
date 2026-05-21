local deps = ...

local logging = deps.logging
local storageService = deps.storage
local widgetHelpers = {
    actions = deps.actions,
    imguiHelpers = deps.imguiHelpers,
    logging = logging,
    widgets = deps.widgets,
}

---@alias Color number[]
---@alias ChoiceValue any
---@alias ChoiceDisplayValues table<any, string>
---@alias ValueColorMap table<any, Color>
---@alias PackedSelectionMode "singleEnabled"|"singleDisabled"

local PACKED_CHOICE_NONE_VALUE = false

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

function widgetHelpers.NormalizeInteger(node, value)
    return storageService.NormalizeInteger(node, value)
end

function widgetHelpers.ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
end

function widgetHelpers.AdvanceInlineGap(imgui, gap)
    if tonumber(gap) and gap > 0 then
        imgui.SetCursorPosX(imgui.GetCursorPosX() + gap)
    end
end

function widgetHelpers.ResolveGap(imgui, value, fallback)
    local gap = tonumber(value)
    if gap == nil or gap < 0 then
        if fallback ~= nil then
            return fallback
        end
        local style = imgui.GetStyle and imgui.GetStyle() or nil
        local spacing = style and style.ItemSpacing or nil
        if type(spacing) == "table" and spacing.x ~= nil then
            return spacing.x
        end
        return 0
    end
    return gap
end

function widgetHelpers.SameLineWithGap(imgui, gap)
    imgui.SameLine()
    widgetHelpers.AdvanceInlineGap(imgui, gap)
end

function widgetHelpers.DrawInlineLabel(imgui, label, tooltip, labelWidth, controlGap)
    local labelText = tostring(label or "")
    if labelText == "" then
        return
    end

    local rowStartX = imgui.GetCursorPosX()
    imgui.AlignTextToFramePadding()
    imgui.Text(labelText)
    widgetHelpers.ShowTooltip(imgui, tooltip)
    imgui.SameLine()

    local targetX = tonumber(labelWidth) and rowStartX + tonumber(labelWidth) or nil
    local currentX = imgui.GetCursorPosX()
    if targetX ~= nil and targetX > currentX then
        imgui.SetCursorPosX(targetX)
    else
        widgetHelpers.AdvanceInlineGap(imgui, widgetHelpers.ResolveGap(imgui, controlGap))
    end
end

function widgetHelpers.DrawWithValueColor(imgui, color, drawFn)
    if type(color) ~= "table" then
        return drawFn()
    end

    local textEnum = imgui.ImGuiCol and imgui.ImGuiCol.Text or 0
    imgui.PushStyleColor(textEnum, color[1], color[2], color[3], color[4])
    local a, b, c, d = drawFn()
    imgui.PopStyleColor()
    return a, b, c, d
end

function widgetHelpers.MakeSelectableId(label, uniqueId)
    return tostring(label or "") .. "##" .. tostring(uniqueId or "")
end

function widgetHelpers.ResolveStorageField(owner, target, methodName)
    return storageService.field.resolve(owner, target, methodName)
end

function widgetHelpers.GetFieldOwner(field)
    return field:owner()
end

function widgetHelpers.StageAction(context, opts, defaultValue)
    local action = opts and opts.action or nil
    if action == nil then
        return
    end
    if widgetHelpers.actions.isDrawActionRef(action) then
        local payload = opts.value
        if payload == nil then
            payload = defaultValue
        end
        action:stage(payload)
        return
    end
    logging.violate(
        "widgets.invalid_action",
        "%s: opts.action must be a draw action ref",
        tostring(context)
    )
end

local function GetPackedChoiceMode(node)
    local mode = node.selectionMode
    if mode == nil or mode == "" then
        return "singleEnabled"
    end
    return mode
end

function widgetHelpers.GetPackedChoiceLabel(node, child)
    if type(node.displayValues) == "table" and node.displayValues[child.alias] ~= nil then
        return tostring(node.displayValues[child.alias])
    end
    return tostring(child.label or child.alias or "")
end

local function IsPackedChoiceActive(mode, value)
    if mode == "singleDisabled" then
        return value == false
    end
    return value == true
end

local function GetPackedChoiceWriteValue(mode, isActive)
    if mode == "singleDisabled" then
        if isActive then
            return false
        end
        return true
    end
    return isActive == true
end

function widgetHelpers.ClassifyPackedChoice(node, field, children)
    local mode = GetPackedChoiceMode(node)
    local owner = widgetHelpers.GetFieldOwner(field)
    local activeCount = 0
    local totalCount = 0
    local lastActiveChild = nil

    for _, child in ipairs(children or {}) do
        totalCount = totalCount + 1
        local value = owner.read(child.alias)
        if value == nil then
            value = PACKED_CHOICE_NONE_VALUE
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
    elseif mode == "singleDisabled" and activeCount == totalCount then
        state = "none"
    end

    return {
        state = state,
        selectedChild = state == "single" and lastActiveChild or nil,
        mode = mode,
        noneValue = PACKED_CHOICE_NONE_VALUE,
    }
end

function widgetHelpers.ApplyPackedChoiceSelection(field, children, selectedAlias, selection)
    local owner = widgetHelpers.GetFieldOwner(field)
    local changed = false
    for _, child in ipairs(children or {}) do
        local shouldBeActive = child.alias == selectedAlias
        local nextValue = GetPackedChoiceWriteValue(selection.mode, shouldBeActive)
        local currentValue = owner.read(child.alias)
        if currentValue == nil then
            currentValue = selection.noneValue
        end
        if currentValue ~= nextValue then
            owner.write(child.alias, nextValue)
            changed = true
        end
    end
    return changed
end

function widgetHelpers.ClearPackedChoiceSelection(field, children, selection)
    local owner = widgetHelpers.GetFieldOwner(field)
    local changed = false
    for _, child in ipairs(children or {}) do
        local currentValue = owner.read(child.alias)
        if currentValue == nil then
            currentValue = selection.noneValue
        end
        if currentValue ~= selection.noneValue then
            owner.write(child.alias, selection.noneValue)
            changed = true
        end
    end
    return changed
end

function widgetHelpers.ResolvePackedChildren(field)
    if not storageService.field.is(field) then
        logging.violate(
            "widgets.invalid_field_target",
            "packed widgets require a StorageField target"
        )
    end

    return storageService.packed.getPackedAliases(field:schema())
end

return widgetHelpers
