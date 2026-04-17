local internal = AdamantModpackLib_Internal
local WidgetFns = public.widgets

local widgetHelpers = internal.widgetHelpers
local NormalizeChoiceValue = widgetHelpers.NormalizeChoiceValue
local ChoiceDisplay = widgetHelpers.ChoiceDisplay
local DrawWithValueColor = widgetHelpers.DrawWithValueColor
local GetPackedChoiceLabel = widgetHelpers.GetPackedChoiceLabel
local ClassifyPackedChoice = widgetHelpers.ClassifyPackedChoice
local ApplyPackedChoiceSelection = widgetHelpers.ApplyPackedChoiceSelection
local ClearPackedChoiceSelection = widgetHelpers.ClearPackedChoiceSelection

---@class RadioOpts
---@field label string|nil
---@field values ChoiceValue[]|nil
---@field default ChoiceValue|nil
---@field displayValues ChoiceDisplayValues|nil
---@field valueColors ValueColorMap|nil
---@field optionsPerLine number|nil
---@field optionGap number|nil

---@class MappedRadioOption
---@field label string|nil
---@field value any
---@field color Color|nil
---@field selected boolean|nil
---@field onSelect fun(option: MappedRadioOption, uiState: UiState): boolean|nil

---@class MappedRadioOpts
---@field label string|nil
---@field optionsPerLine number|nil
---@field optionGap number|nil
---@field getOptions fun(view: table<string, any>): MappedRadioOption[]|any[]

---@class PackedRadioOpts
---@field label string|nil
---@field displayValues ChoiceDisplayValues|nil
---@field valueColors table<string, Color>|nil
---@field noneLabel string|nil
---@field selectionMode PackedSelectionMode|nil
---@field optionsPerLine number|nil
---@field optionGap number|nil

---@class RadioOptionEntry
---@field label string
---@field color Color|nil
---@field selected boolean
---@field onSelect fun(): boolean

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

---@param imgui table
---@param radioId string
---@param labelText string
---@param optionEntries RadioOptionEntry[]
---@param optionsPerLine number|nil
---@param optionGap number|nil
---@return boolean
local function DrawRadioOptions(imgui, radioId, labelText, optionEntries, optionsPerLine, optionGap)
    local changed = false
    local normalizedPerLine = math.floor(tonumber(optionsPerLine) or 0)
    if normalizedPerLine < 1 then
        normalizedPerLine = #optionEntries
    end
    local normalizedGap = tonumber(optionGap)
    if normalizedGap == nil or normalizedGap < 0 then
        normalizedGap = imgui.GetStyle().ItemSpacing.x
    end

    if labelText ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(labelText)
    end

    for index, option in ipairs(optionEntries) do
        local positionInLine = (index - 1) % normalizedPerLine
        if positionInLine ~= 0 then
            imgui.SameLine()
            if normalizedGap > 0 then
                imgui.SetCursorPosX(imgui.GetCursorPosX() + normalizedGap)
            end
        end

        local clicked = DrawWithValueColor(imgui, option.color, function()
            return imgui.RadioButton(option.label .. "##" .. tostring(radioId) .. "_" .. tostring(index), option.selected == true)
        end)
        if clicked and type(option.onSelect) == "function" and option.onSelect() == true then
            changed = true
        end
    end

    return changed
end

---@param imgui table
---@param uiState UiState
---@param alias string
---@param opts RadioOpts|nil
---@return boolean
function WidgetFns.radio(imgui, uiState, alias, opts)
    opts = opts or {}
    local current = NormalizeChoiceValue(opts, uiState.view[alias])
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local optionEntries = {}

    for _, value in ipairs(opts.values or {}) do
        optionEntries[#optionEntries + 1] = {
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

    return DrawRadioOptions(
        imgui,
        alias,
        tostring(opts.label or ""),
        optionEntries,
        opts.optionsPerLine,
        opts.optionGap
    )
end

---@param imgui table
---@param uiState UiState
---@param alias string
---@param opts MappedRadioOpts|nil
---@return boolean
function WidgetFns.mappedRadio(imgui, uiState, alias, opts)
    opts = opts or {}
    local current = uiState.view[alias]
    local optionEntries = {}

    for _, option in ipairs(type(opts.getOptions) == "function" and (opts.getOptions(uiState.view) or {}) or {}) do
        local label = type(option) == "table" and tostring(option.label or option.value or "") or tostring(option)
        local color = type(option) == "table" and option.color or nil
        local selected = type(option) == "table" and option.selected == true or current == option
        optionEntries[#optionEntries + 1] = {
            label = label,
            color = color,
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

    return DrawRadioOptions(
        imgui,
        alias,
        tostring(opts.label or ""),
        optionEntries,
        opts.optionsPerLine,
        opts.optionGap
    )
end

---@param imgui table
---@param uiState UiState
---@param alias string
---@param store ManagedStore|nil
---@param opts PackedRadioOpts|nil
---@return boolean
function WidgetFns.packedRadio(imgui, uiState, alias, store, opts)
    opts = opts or {}
    local children = ResolvePackedChildren(uiState, alias, store)
    local selection = ClassifyPackedChoice(opts, children)
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local optionEntries = {
        {
            label = tostring(opts.noneLabel or "None"),
            selected = selection.state == "none",
            onSelect = function()
                return ClearPackedChoiceSelection(children, selection) == true
            end,
        },
    }

    for _, child in ipairs(children) do
        optionEntries[#optionEntries + 1] = {
            label = GetPackedChoiceLabel(opts, child),
            color = valueColors and valueColors[child.alias] or nil,
            selected = selection.selectedChild and selection.selectedChild.alias == child.alias or false,
            onSelect = function()
                return ApplyPackedChoiceSelection(children, child.alias, selection) == true
            end,
        }
    end

    return DrawRadioOptions(
        imgui,
        alias,
        tostring(opts.label or ""),
        optionEntries,
        opts.optionsPerLine,
        opts.optionGap
    )
end
