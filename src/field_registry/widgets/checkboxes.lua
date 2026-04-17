local internal = AdamantModpackLib_Internal
local widgets = internal.widgets
local WidgetFns = public.widgets

local choiceHelpers = widgets.choiceHelpers
local DrawWithValueColor = choiceHelpers.DrawWithValueColor

local DEFAULT_PACKED_SLOT_COUNT = 32

local function ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and type(imgui.IsItemHovered) == "function" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
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

function WidgetFns.checkbox(imgui, uiState, alias, opts)
    opts = opts or {}
    local label = tostring(opts.label or alias or "")
    local current = uiState.view[alias] == true
    local nextValue, changed = imgui.Checkbox(label .. "##" .. tostring(alias), current)
    ShowTooltip(imgui, opts.tooltip)
    if changed then
        uiState.set(alias, nextValue)
        return true
    end
    return false
end

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
