local internal = AdamantModpackLib_Internal
local ui = internal.ui
local widgets = internal.widgets
local WidgetFns = public.widgets

local NormalizeChoiceValue = ui.NormalizeChoiceValue
local ChoiceDisplay = widgets.ChoiceDisplay
local CalcTextWidth = ui.CalcTextWidth
local GetStyleMetricX = ui.GetStyleMetricX
local EstimateStructuredRowAdvanceY = ui.EstimateStructuredRowAdvanceY
local EstimateToggleWidth = ui.EstimateToggleWidth
local DrawOrderedEntries = ui.DrawOrderedEntries

local choiceHelpers = widgets.choiceHelpers
local DrawWithValueColor = choiceHelpers.DrawWithValueColor
local GetPackedChoiceLabel = choiceHelpers.GetPackedChoiceLabel
local ClassifyPackedChoice = choiceHelpers.ClassifyPackedChoice
local ApplyPackedChoiceSelection = choiceHelpers.ApplyPackedChoiceSelection
local ClearPackedChoiceSelection = choiceHelpers.ClearPackedChoiceSelection

local function CompareEntries(left, right)
    if left.line ~= right.line then
        return left.line < right.line
    end
    if type(left.start) == "number" and type(right.start) == "number" and left.start ~= right.start then
        return left.start < right.start
    end
    return left.index < right.index
end

local function BuildOrderedChoiceEntries(labelText, optionEntries, optionGap)
    local entries = {}

    local function OptionGap(imgui)
        if type(optionGap) == "number" and optionGap >= 0 then
            return optionGap
        end
        local style = type(imgui.GetStyle) == "function" and imgui.GetStyle() or nil
        return GetStyleMetricX(style, "ItemSpacing", 8)
    end

    local function AddEntry(name, config)
        entries[#entries + 1] = {
            index = #entries + 1,
            name = name,
            line = config.line or 1,
            start = config.start,
            width = config.width,
            align = config.align,
            estimateWidth = config.estimateWidth,
            render = config.render,
        }
    end

    if type(labelText) == "string" and labelText ~= "" then
        AddEntry("label", {
            estimateWidth = function(imgui)
                return CalcTextWidth(imgui, labelText)
            end,
            render = function(imgui)
                imgui.AlignTextToFramePadding()
                imgui.Text(labelText)
                return false, CalcTextWidth(imgui, labelText), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
    end

    for index, option in ipairs(optionEntries or {}) do
        local slotName = option.slotName or ("option:" .. tostring(index))
        AddEntry(slotName, {
            estimateWidth = function(imgui)
                return EstimateToggleWidth(imgui, option.label)
            end,
            render = function(imgui)
                local clicked = DrawWithValueColor(imgui, option.color, function()
                    return imgui.RadioButton(option.label, option.selected == true)
                end)
                if clicked and type(option.onSelect) == "function" then
                    return option.onSelect() == true, EstimateToggleWidth(imgui, option.label), EstimateStructuredRowAdvanceY(imgui)
                end
                return false, EstimateToggleWidth(imgui, option.label), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
        if index < #optionEntries then
            AddEntry(slotName .. ":gap", {
                estimateWidth = function(imgui)
                    return OptionGap(imgui)
                end,
                render = function(imgui)
                    return false, OptionGap(imgui), EstimateStructuredRowAdvanceY(imgui)
                end,
            })
        end
    end

    table.sort(entries, CompareEntries)
    return entries
end

local function ResolvePackedChildren(uiState, alias, store)
    local aliasNode = uiState and uiState.getAliasNode and uiState.getAliasNode(alias) or nil
    local children = {}
    if store and type(store.getPackedAliases) == "function" then
        for _, child in ipairs(store.getPackedAliases(alias) or {}) do
            children[#children + 1] = {
                alias = child.alias,
                label = child.label or child.alias,
                get = function() return uiState.view[child.alias] end,
                set = function(value) uiState.set(child.alias, value) end,
            }
        end
        if #children > 0 then
            return children
        end
    end
    for _, child in ipairs(aliasNode and aliasNode._bitAliases or {}) do
        children[#children + 1] = {
            alias = child.alias,
            label = child.label or child.alias,
            get = function() return uiState.view[child.alias] end,
            set = function(value) uiState.set(child.alias, value) end,
        }
    end
    return children
end

function WidgetFns.radio(imgui, uiState, alias, opts)
    opts = opts or {}
    local current = NormalizeChoiceValue(opts, uiState.view[alias])
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local optionEntries = {}
    for index, value in ipairs(opts.values or {}) do
        optionEntries[#optionEntries + 1] = {
            slotName = "option:" .. tostring(index),
            label = ChoiceDisplay(opts, value),
            color = valueColors and valueColors[value] or nil,
            selected = current == value,
            onSelect = function()
                if current ~= value then
                    uiState.set(alias, value)
                    current = value
                    return true
                end
                return false
            end,
        }
    end
    local _, _, changed = DrawOrderedEntries(
        imgui,
        BuildOrderedChoiceEntries(tostring(opts.label or ""), optionEntries, opts.optionGap),
        ui.GetCursorPosXSafe(imgui),
        ui.GetCursorPosYSafe(imgui),
        EstimateStructuredRowAdvanceY(imgui))
    return changed
end

function WidgetFns.mappedRadio(imgui, uiState, alias, opts)
    opts = opts or {}
    local current = uiState.view[alias]
    local optionEntries = {}
    for index, option in ipairs(type(opts.getOptions) == "function" and (opts.getOptions(uiState.view) or {}) or {}) do
        local label = type(option) == "table" and tostring(option.label or option.value or "") or tostring(option)
        local selected = type(option) == "table" and option.selected == true or current == option
        optionEntries[#optionEntries + 1] = {
            slotName = "option:" .. tostring(index),
            label = label,
            selected = selected,
            onSelect = function()
                if type(option) == "table" and type(option.onSelect) == "function" then
                    return option.onSelect(option, uiState) == true
                end
                local nextValue = type(option) == "table" and option.value or option
                if nextValue ~= current then
                    uiState.set(alias, nextValue)
                    current = nextValue
                    return true
                end
                return false
            end,
        }
    end
    local _, _, changed = DrawOrderedEntries(
        imgui,
        BuildOrderedChoiceEntries(tostring(opts.label or ""), optionEntries, opts.optionGap),
        ui.GetCursorPosXSafe(imgui),
        ui.GetCursorPosYSafe(imgui),
        EstimateStructuredRowAdvanceY(imgui))
    return changed
end

function WidgetFns.packedRadio(imgui, uiState, alias, store, opts)
    opts = opts or {}
    local children = ResolvePackedChildren(uiState, alias, store)
    local selection = ClassifyPackedChoice(opts, children)
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local optionEntries = {
        {
            slotName = "option:none",
            label = tostring(opts.noneLabel or "None"),
            selected = selection.state == "none",
            onSelect = function()
                return ClearPackedChoiceSelection(children, selection) == true
            end,
        },
    }
    for index, child in ipairs(children) do
        optionEntries[#optionEntries + 1] = {
            slotName = "option:" .. tostring(index),
            label = GetPackedChoiceLabel(opts, child),
            color = valueColors and valueColors[child.alias] or nil,
            selected = selection.selectedChild and selection.selectedChild.alias == child.alias or false,
            onSelect = function()
                return ApplyPackedChoiceSelection(children, child.alias, selection) == true
            end,
        }
    end
    local _, _, changed = DrawOrderedEntries(
        imgui,
        BuildOrderedChoiceEntries(tostring(opts.label or ""), optionEntries, opts.optionGap),
        ui.GetCursorPosXSafe(imgui),
        ui.GetCursorPosYSafe(imgui),
        EstimateStructuredRowAdvanceY(imgui))
    return changed
end
