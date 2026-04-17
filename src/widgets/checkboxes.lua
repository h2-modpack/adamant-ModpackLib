local internal = AdamantModpackLib_Internal
local WidgetFns = public.widgets

local widgetHelpers = internal.widgetHelpers
local DrawWithValueColor = widgetHelpers.DrawWithValueColor
local NormalizeColor = widgetHelpers.NormalizeColor

local DEFAULT_PACKED_SLOT_COUNT = 32

---@class CheckboxOpts
---@field label string|nil
---@field tooltip string|nil
---@field color Color|nil

---@class PackedCheckboxListOpts
---@field filterText string|nil
---@field filterMode "all"|"checked"|"unchecked"|nil
---@field valueColors table<string, Color>|nil
---@field slotCount number|nil
---@field optionsPerLine number|nil
---@field optionGap number|nil

local function ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
end

local function ResolveOptionGap(imgui, optionGap)
    local normalizedGap = tonumber(optionGap)
    if normalizedGap == nil or normalizedGap < 0 then
        normalizedGap = 8
    end
    return normalizedGap
end

local function ResolvePackedChildren(uiState, alias, store)
    local aliasNode = uiState and uiState.getAliasNode and uiState.getAliasNode(alias) or nil
    local result = {}
    if store and type(store.getPackedAliases) == "function" then
        for _, child in ipairs(store.getPackedAliases(alias) or {}) do
            result[#result + 1] = {
                alias = child.alias,
                label = child.label or child.alias,
                get = function() return uiState.view[child.alias] end,
                set = function(value) uiState.set(child.alias, value) end,
            }
        end
        if #result > 0 then
            return result
        end
    end
    for _, child in ipairs(aliasNode and aliasNode._bitAliases or {}) do
        result[#result + 1] = {
            alias = child.alias,
            label = child.label or child.alias,
            get = function() return uiState.view[child.alias] end,
            set = function(value) uiState.set(child.alias, value) end,
        }
    end
    return result
end

---@param imgui table
---@param uiState UiState
---@param alias string
---@param opts CheckboxOpts|nil
---@return boolean
function WidgetFns.checkbox(imgui, uiState, alias, opts)
    opts = opts or {}
    local label = tostring(opts.label or alias or "")
    local current = uiState.view[alias] == true
    local color = NormalizeColor(opts.color)
    local nextValue, changed = DrawWithValueColor(imgui, color, function()
        return imgui.Checkbox(label .. "##" .. tostring(alias), current)
    end)
    ShowTooltip(imgui, opts.tooltip)
    if changed then
        uiState.set(alias, nextValue)
        return true
    end
    return false
end

---@param imgui table
---@param uiState UiState
---@param alias string
---@param store ManagedStore|nil
---@param opts PackedCheckboxListOpts|nil
---@return boolean
function WidgetFns.packedCheckboxList(imgui, uiState, alias, store, opts)
    opts = opts or {}
    local children = ResolvePackedChildren(uiState, alias, store)
    local lowerFilter = type(opts.filterText) == "string" and opts.filterText:lower() or ""
    local hasFilter = lowerFilter ~= ""
    local filterMode = opts.filterMode
    if filterMode ~= "checked" and filterMode ~= "unchecked" then
        filterMode = "all"
    end
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local slotCount = math.max(math.floor(tonumber(opts.slotCount) or DEFAULT_PACKED_SLOT_COUNT), 1)
    local optionsPerLine = math.floor(tonumber(opts.optionsPerLine) or 0)
    if optionsPerLine < 1 then
        optionsPerLine = 1
    end
    local optionGap = ResolveOptionGap(imgui, opts.optionGap)
    local drawn = 0
    local changed = false

    for _, child in ipairs(children) do
        if drawn >= slotCount then
            break
        end
        local current = child.get() == true
        local matchesText = not hasFilter or tostring(child.label):lower():find(lowerFilter, 1, true) ~= nil
        local matchesMode = filterMode == "all"
            or (filterMode == "checked" and current)
            or (filterMode == "unchecked" and not current)
        if matchesText and matchesMode then
            drawn = drawn + 1
            local positionInLine = (drawn - 1) % optionsPerLine
            if positionInLine ~= 0 then
                imgui.SameLine()
                if optionGap > 0 then
                    imgui.SetCursorPosX(imgui.GetCursorPosX() + optionGap)
                end
            end
            local color = valueColors and valueColors[child.alias] or nil
            local nextValue, clicked = DrawWithValueColor(imgui, color, function()
                return imgui.Checkbox(tostring(child.label) .. "##" .. tostring(child.alias), current)
            end)
            if clicked then
                child.set(nextValue)
                changed = true
            end
        end
    end

    return changed
end
