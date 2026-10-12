local deps = ...

-- The "Modded" stamp shown on the victory (RunClear) screen while a stamp overlay is eligible.
local overlayGameDeps = deps.gameDeps
local values = deps.values
local hudComponents = deps.hudComponents
local stampLayout = deps.stampLayout
local rendererState = deps.state

local victoryStamp = {}

function victoryStamp.isScreenOpen()
    local screens = overlayGameDeps.ActiveScreens()
    return screens ~= nil and screens.RunClear ~= nil
end

--- Creates or removes the stamp to match `eligible`.
---@param eligible boolean
---@return boolean changed True when the stamp was created or removed.
function victoryStamp.sync(eligible)
    local entry = rendererState.victoryStamp
    if not eligible then
        if not entry then
            return false
        end
        hudComponents.discard(entry)
        local data = overlayGameDeps.ScreenData()
        if data and data.HUD and data.HUD.ComponentData then
            data.HUD.ComponentData[entry.componentName] = nil
        end
        rendererState.victoryStamp = nil
        return true
    end

    local created = entry == nil
    if created then
        entry = {
            componentName = "AdamantVictoryStamp",
            layout = values.deepCopy(stampLayout),
            textArgs = {},
        }
        rendererState.victoryStamp = entry
    end
    local previousId = entry.componentId
    local component = hudComponents.ensure(entry)
    if component and previousId ~= component.Id then
        overlayGameDeps.ModifyTextBox({ Id = component.Id, Text = "Modded" })
        overlayGameDeps.SetAlpha({ Id = component.Id, Fraction = 1.0, Duration = 0.0 })
    end
    return created
end

return victoryStamp
