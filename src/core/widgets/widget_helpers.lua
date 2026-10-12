local deps = ...

local logging = deps.logging
local storageApi = deps.storage
local isDrawActionRef = deps.isDrawActionRef
local widgetHelpers = {}
widgetHelpers.EMPTY_OPTS = {}
widgetHelpers.EMPTY_LIST = {}

local PACKED_CHOICE_NONE_VALUE = false

local function ReadColorComponents(value)
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
    return r, g, b, a
end

function widgetHelpers.IsChoiceVisible(node, value)
    return type(node.visibleValues) ~= "table" or node.visibleValues[value] ~= false
end

--- Display text for one choice value: `opts.displayValues`, then `fallbackDisplayValues`
--- (e.g. generated range labels), then the raw value. A nil value renders as "".
function widgetHelpers.ChoiceDisplay(opts, value, fallbackDisplayValues)
    if value == nil then
        return ""
    end
    if opts.displayValues and opts.displayValues[value] ~= nil then
        return tostring(opts.displayValues[value])
    end
    if fallbackDisplayValues and fallbackDisplayValues[value] ~= nil then
        return tostring(fallbackDisplayValues[value])
    end
    return tostring(value)
end

function widgetHelpers.ValueColors(opts)
    return type(opts.valueColors) == "table" and opts.valueColors or nil
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

--- Draws the optional inline label and pushes `opts.controlWidth` (or `defaultWidth`) as the
--- item width. Pair with `EndLabeledControl`.
---@return boolean pushedWidth
function widgetHelpers.BeginLabeledControl(imgui, opts, defaultWidth)
    local labelText = tostring(opts.label or "")
    local controlWidth = tonumber(opts.controlWidth) or defaultWidth

    if labelText ~= "" then
        widgetHelpers.DrawInlineLabel(imgui, labelText, opts.tooltip, opts.labelWidth, opts.controlGap)
    end

    if controlWidth > 0 then
        imgui.PushItemWidth(controlWidth)
        return true
    end
    return false
end

function widgetHelpers.EndLabeledControl(imgui, opts, pushedWidth)
    if pushedWidth then
        imgui.PopItemWidth()
    end
    widgetHelpers.ShowTooltip(imgui, opts.tooltip)
end

--- Draws a frame-aligned leading label; returns whether anything was drawn.
function widgetHelpers.DrawRowLabel(imgui, labelText)
    if labelText == "" then
        return false
    end
    imgui.AlignTextToFramePadding()
    imgui.Text(labelText)
    return true
end

function widgetHelpers.PushValueColor(imgui, color)
    local r, g, b, a = ReadColorComponents(color)
    if r == nil then
        return false
    end

    local textEnum = imgui.ImGuiCol and imgui.ImGuiCol.Text or 0
    imgui.PushStyleColor(textEnum, r, g, b, a)
    return true
end

function widgetHelpers.PopValueColor(imgui, pushed)
    if pushed then
        imgui.PopStyleColor()
    end
end

function widgetHelpers.SelectableWithValueColor(imgui, label, selected, color)
    local pushed = widgetHelpers.PushValueColor(imgui, color)
    local clicked = imgui.Selectable(label, selected)
    widgetHelpers.PopValueColor(imgui, pushed)
    return clicked
end

function widgetHelpers.CheckboxWithValueColor(imgui, label, current, color)
    local pushed = widgetHelpers.PushValueColor(imgui, color)
    local nextValue, changed = imgui.Checkbox(label, current)
    widgetHelpers.PopValueColor(imgui, pushed)
    return nextValue, changed
end

function widgetHelpers.RadioButtonWithValueColor(imgui, label, selected, color)
    local pushed = widgetHelpers.PushValueColor(imgui, color)
    local clicked = imgui.RadioButton(label, selected)
    widgetHelpers.PopValueColor(imgui, pushed)
    return clicked
end

function widgetHelpers.TextWithValueColor(imgui, color, text)
    local r, g, b, a = ReadColorComponents(color)
    if r == nil then
        return false
    end
    imgui.TextColored(r, g, b, a, text)
    return true
end

function widgetHelpers.MakeSelectableId(label, uniqueId)
    return tostring(label or "") .. "##" .. tostring(uniqueId or "")
end

function widgetHelpers.StageAction(context, opts, defaultValue)
    local action = opts and opts.action or nil
    if action == nil then
        return
    end
    if isDrawActionRef(action) then
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
    local activeCount = 0
    local totalCount = 0
    local lastActiveChild = nil

    for _, child in ipairs(children or widgetHelpers.EMPTY_LIST) do
        totalCount = totalCount + 1
        local value = field:readAlias(child.alias)
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
    local changed = false
    for _, child in ipairs(children or widgetHelpers.EMPTY_LIST) do
        local shouldBeActive = child.alias == selectedAlias
        local nextValue = GetPackedChoiceWriteValue(selection.mode, shouldBeActive)
        local currentValue = field:readAlias(child.alias)
        if currentValue == nil then
            currentValue = selection.noneValue
        end
        if currentValue ~= nextValue then
            field:writeAlias(child.alias, nextValue)
            changed = true
        end
    end
    return changed
end

function widgetHelpers.ClearPackedChoiceSelection(field, children, selection)
    local changed = false
    for _, child in ipairs(children or widgetHelpers.EMPTY_LIST) do
        local currentValue = field:readAlias(child.alias)
        if currentValue == nil then
            currentValue = selection.noneValue
        end
        if currentValue ~= selection.noneValue then
            field:writeAlias(child.alias, selection.noneValue)
            changed = true
        end
    end
    return changed
end

function widgetHelpers.ResolvePackedChildren(field)
    if not storageApi.field.is(field) then
        logging.violate(
            "widgets.invalid_field_target",
            "packed widgets require a StorageField target"
        )
    end

    return storageApi.packed.getPackedAliases(field:schema())
end

return widgetHelpers
