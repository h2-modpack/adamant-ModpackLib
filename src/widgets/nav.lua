public.nav = public.nav or {}
local nav = public.nav

---@class NavTab
---@field key string|number
---@field label string|nil
---@field group string|nil
---@field color Color|nil

---@class VerticalTabsOpts
---@field id string|number|nil
---@field navWidth number|nil
---@field height number|nil
---@field tabs NavTab[]|nil
---@field activeKey string|number|nil

---@class VisibilityCondition
---@field alias string
---@field value any
---@field anyOf any[]|nil

local function NormalizeTabs(tabs)
    if type(tabs) ~= "table" then
        return {}
    end
    return tabs
end

---@param imgui table
---@param opts VerticalTabsOpts|nil
---@return string|number|nil
function nav.verticalTabs(imgui, opts)
    opts = opts or {}
    local id = tostring(opts.id or "verticalTabs")
    local navWidth = tonumber(opts.navWidth) or 180
    local height = tonumber(opts.height) or 0
    local tabs = NormalizeTabs(opts.tabs)
    local activeKey = opts.activeKey

    imgui.BeginChild(id .. "##nav", navWidth, height, true)
    local currentGroup = nil
    for _, tab in ipairs(tabs) do
        local key = tab.key
        local label = tostring(tab.label or key or "")
        local itemId = label .. "##" .. tostring(key)
        local group = type(tab.group) == "string" and tab.group or nil
        local selected = key == activeKey
        local color = tab.color
        if group ~= nil and group ~= currentGroup then
            if currentGroup ~= nil then
                imgui.Separator()
            end
            if type(imgui.TextDisabled) == "function" then
                imgui.TextDisabled(group)
            else
                imgui.Text(group)
            end
            
            imgui.Separator()
            
            currentGroup = group
        end
        if type(color) == "table" then
            local textEnum = imgui.ImGuiCol and imgui.ImGuiCol.Text or 0
            imgui.PushStyleColor(textEnum, color[1], color[2], color[3], color[4] or 1)
        end
        if imgui.Selectable(itemId, selected) then
            activeKey = key
        end
        if type(color) == "table" then
            imgui.PopStyleColor()
        end
    end
    imgui.EndChild()
    imgui.SameLine()

    return activeKey
end

---@param uiState UiState|nil
---@param condition string|VisibilityCondition|nil
---@return boolean
function nav.isVisible(uiState, condition)
    if condition == nil then
        return true
    end
    local view = uiState and uiState.view or nil
    if type(condition) == "string" then
        return view and view[condition] == true or false
    end
    if type(condition) ~= "table" then
        return true
    end

    local alias = condition.alias
    if type(alias) ~= "string" or alias == "" then
        return false
    end

    local value = view and view[alias]
    if condition.value ~= nil then
        return value == condition.value
    end
    if condition.anyOf ~= nil then
        if type(condition.anyOf) ~= "table" then
            return false
        end
        for _, candidate in ipairs(condition.anyOf) do
            if value == candidate then
                return true
            end
        end
        return false
    end

    return value == true
end
