local fallbackHud = {}

local COMPONENT_NAME = "ModpackMark_StandaloneLib"
local HUD_Y = 250
local MARKER_TEXT = "Modded"

local function isFrameworkInstalled()
    return rom
        and rom.mods
        and rom.mods["adamant-ModpackFramework"] ~= nil
end

local function shouldShowFallbackMarker()
    if isFrameworkInstalled() then
        return false
    end
    return true
end

function fallbackHud.createMarker()
    if fallbackHud._initialized then
        return
    end
    fallbackHud._initialized = true

    if not (ScreenData and ScreenData.HUD and ScreenData.HUD.ComponentData) then
        return
    end

    ScreenData.HUD.ComponentData[COMPONENT_NAME] = {
        RightOffset = 20,
        Y = HUD_Y,
        TextArgs = {
            Text = "",
            Font = "MonospaceTypewriterBold",
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
        },
    }

    local displayedText = nil

    local function updateMarker()
        if not HUDScreen or not HUDScreen.Components or not HUDScreen.Components[COMPONENT_NAME] then
            return
        end

        local nextText = shouldShowFallbackMarker() and MARKER_TEXT or ""
        if nextText == displayedText then
            return
        end

        local component = HUDScreen.Components[COMPONENT_NAME]
        if nextText == "" then
            ModifyTextBox({ Id = component.Id, ClearText = true })
        else
            ModifyTextBox({ Id = component.Id, Text = nextText })
        end
        displayedText = nextText
    end

    modutil.mod.Path.Wrap("ShowHealthUI", function(base, args)
        base(args)
        displayedText = nil
        updateMarker()
    end)
end

return fallbackHud
