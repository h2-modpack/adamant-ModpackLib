local deps = ...

-- Game-API adapter for the HUD text components backing overlay text entries.
local overlayGameDeps = deps.gameDeps
local values = deps.values
local groupDestinations = deps.groupDestinations

local hudComponents = {}

-- Game HUD fonts. `label` is the default; `numeric` has tabular digits for aligned timers and counters.
hudComponents.FONTS = {
    label = "P22UndergroundSCMedium",
    numeric = "NumericP22UndergroundSCMedium",
}

local DEFAULT_TEXT_ARGS = {
    Text = "",
    Font = hudComponents.FONTS.label,
    FontSize = 18,
    Color = { 1, 1, 1, 1 },
    ShadowRed = 0.1,
    ShadowBlue = 0.1,
    ShadowGreen = 0.1,
    OutlineColor = { 0.113, 0.113, 0.113, 1 },
    OutlineThickness = 2,
    ShadowAlpha = 1.0,
    ShadowBlur = 1,
    ShadowOffset = { 0, 4 },
    Justification = "Right",
    VerticalJustification = "Top",
    DataProperties = { OpacityWithOwner = true },
}

function hudComponents.sanitizeName(id)
    return "AdamantOverlay_" .. tostring(id):gsub("[^%w_%-]", "_")
end

function hudComponents.layoutSignature(layout)
    layout = layout or {}
    return table.concat({
        tostring(layout.Anchor),
        tostring(layout.X),
        tostring(layout.Y),
        tostring(layout.RightOffset),
        tostring(layout.BottomOffset),
    }, "|")
end

--- Writes the entry's HUD component data (layout + text args, blank text).
function hudComponents.ensureData(entry)
    local screenData = overlayGameDeps.ScreenData()
    if not (screenData and screenData.HUD and screenData.HUD.ComponentData) then
        return false
    end

    local data = values.deepCopy(entry.layout or {})
    data.Name = data.Name or "BlankObstacle"
    data.GroupName = data.GroupName or "HUD_Overlay"
    data.Alpha = data.Alpha or 1.0
    data.AlphaTarget = data.AlphaTarget or 1.0
    data.TextArgs = values.deepCopy(DEFAULT_TEXT_ARGS)
    for key, value in pairs(entry.textArgs or {}) do
        data.TextArgs[key] = values.deepCopy(value)
    end
    data.TextArgs.Text = ""
    screenData.HUD.ComponentData[entry.componentName] = data
    return true
end

--- Destroys the entry's live HUD component, if any, and forgets what it displayed.
function hudComponents.discard(entry)
    local hudScreen = overlayGameDeps.HUDScreen()
    local component = hudScreen and hudScreen.Components and hudScreen.Components[entry.componentName]
    if not component then
        return
    end

    if component.Id ~= nil then
        overlayGameDeps.Destroy({ Id = component.Id })
    end
    hudScreen.Components[entry.componentName] = nil
    entry.displayedText = nil
    entry.displayedVisible = nil
    entry.componentLayoutSignature = nil
    entry.componentId = nil
end

--- Returns the entry's live HUD component, creating it from component data when missing.
function hudComponents.ensure(entry)
    if entry.deferUntilLayout == true and entry.layoutSignature == nil then
        hudComponents.ensureData(entry)
        return nil
    end

    hudComponents.ensureData(entry)

    local hudScreen = overlayGameDeps.HUDScreen()
    if not hudScreen or not hudScreen.Components then
        return nil
    end

    local component = hudScreen.Components[entry.componentName]
    local screenData = overlayGameDeps.ScreenData()
    if not component and screenData and screenData.HUD and screenData.HUD.ComponentData then
        local componentData = screenData.HUD.ComponentData[entry.componentName]
        if componentData then
            component = overlayGameDeps.CreateComponentFromData(screenData.HUD.ComponentData, componentData)
            if component then
                component.Screen = hudScreen
                hudScreen.Components[entry.componentName] = component
                entry.componentLayoutSignature = hudComponents.layoutSignature(entry.layout)
                local groupName = entry.layout.GroupName
                local destination = groupName and groupDestinations[groupName] or nil
                if destination then
                    overlayGameDeps.InsertGroupInFront({
                        Name = groupName,
                        DestinationName = destination,
                    })
                end
            end
        end
    end

    if not component then
        return nil
    end

    if entry.componentId ~= component.Id then
        entry.componentId = component.Id
        entry.displayedText = nil
        entry.displayedVisible = nil
        entry.componentLayoutSignature = entry.componentLayoutSignature or hudComponents.layoutSignature(entry.layout)
    end

    return component
end

return hudComponents
