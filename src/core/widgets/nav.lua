local nav = {}
local EMPTY_OPTS = {}
local EMPTY_TABS = {}

local function NormalizeTabs(tabs)
    if type(tabs) ~= "table" then
        return EMPTY_TABS
    end
    return tabs
end

function nav.verticalTabs(imgui, opts)
    opts = opts or EMPTY_OPTS
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
            imgui.TextDisabled(group)
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

return nav
