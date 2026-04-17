public.ui = public.ui or {}
local ui = public.ui

local function NormalizeTabs(tabs)
    if type(tabs) ~= "table" then
        return {}
    end
    return tabs
end

function ui.verticalTabs(imgui, opts)
    opts = opts or {}
    local id = tostring(opts.id or "verticalTabs")
    local navWidth = tonumber(opts.navWidth) or 180
    local height = tonumber(opts.height) or 0
    local tabs = NormalizeTabs(opts.tabs)
    local activeKey = opts.activeKey

    imgui.BeginChild(id .. "##nav", navWidth, height, true)
    for _, tab in ipairs(tabs) do
        local key = tab.key
        local label = tostring(tab.label or key or "")
        local selected = key == activeKey
        local color = tab.color
        if type(color) == "table" and type(imgui.PushStyleColor) == "function" and type(imgui.PopStyleColor) == "function" then
            local textEnum = imgui.ImGuiCol and imgui.ImGuiCol.Text or 0
            imgui.PushStyleColor(textEnum, color[1], color[2], color[3], color[4] or 1)
        end
        if imgui.Selectable(label, selected) then
            activeKey = key
        end
        if type(color) == "table" and type(imgui.PopStyleColor) == "function" then
            imgui.PopStyleColor()
        end
    end
    imgui.EndChild()
    imgui.SameLine()

    return activeKey
end

function ui.isVisible(uiState, condition)
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
