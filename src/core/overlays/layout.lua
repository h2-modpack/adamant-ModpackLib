local deps = ...

-- Stateless stack-layout math: managed region geometry, order bands, and column placement.
local overlayGameDeps = deps.gameDeps
local overlayOrder = deps.order
local values = deps.values

local layout = {}

local VICTORY_STAMP_GROUP = "AdamantVictoryStamp"
local VICTORY_ROW_HEIGHT = 28
local VICTORY_ROW_GAP = 4

layout.VICTORY_REGION = "victoryStack"
layout.VICTORY_STAMP_LAYOUT = { Anchor = "right", RightOffset = 24, Y = 28, GroupName = VICTORY_STAMP_GROUP }

-- HUD groups inserted in front of a game group when one of their components is created.
layout.GROUP_DESTINATIONS = {
    [VICTORY_STAMP_GROUP] = "Combat_Menu_TraitTray_Overlay_Additive",
}

layout.REGIONS = {
    middleRightStack = {
        anchor = "right",
        RightOffset = 10,
        Y = 200,
        itemHeight = 28,
        gap = 4,
        groupGap = 12,
        justification = "Right",
        verticalJustification = "Top",
        fontSize = 18,
    },
    centerLowerStack = {
        anchor = "center",
        X = function()
            return overlayGameDeps.ScreenCenterX() or 960
        end,
        Y = function()
            return (overlayGameDeps.ScreenHeight() or 1080) * 0.60
        end,
        itemHeight = 32,
        gap = 4,
        groupGap = 12,
        justification = "Center",
        verticalJustification = "Center",
        fontSize = 22,
    },
    -- Rows beneath the Modded stamp on the RunClear screen; shown only while that stamp is.
    [layout.VICTORY_REGION] = {
        anchor = "right",
        RightOffset = layout.VICTORY_STAMP_LAYOUT.RightOffset,
        Y = layout.VICTORY_STAMP_LAYOUT.Y + VICTORY_ROW_HEIGHT + VICTORY_ROW_GAP,
        itemHeight = VICTORY_ROW_HEIGHT,
        gap = VICTORY_ROW_GAP,
        groupGap = 12,
        justification = "Right",
        verticalJustification = "Top",
        -- Default HUD text size.
        fontSize = 18,
        groupName = VICTORY_STAMP_GROUP,
    },
}

local function resolveValue(value)
    if type(value) == "function" then
        return value()
    end
    return value
end

local function overlayOrderBand(order)
    if order >= overlayOrder.debug then
        return "debug"
    end
    if order >= overlayOrder.module then
        return "module"
    end
    if order >= overlayOrder.modpack then
        return "modpack"
    end
    return "system"
end

--- Places `entries` (sorted, visible stack rows) top to bottom in `region`, adding the
--- region's group gap between order bands. Calls `place(entry, rowLayout, rowTextArgs)`.
function layout.placeRows(region, entries, place)
    local y = resolveValue(region.Y)
    local x = resolveValue(region.X)
    local rightOffset = resolveValue(region.RightOffset)
    local previousBand = nil
    for index, entry in ipairs(entries) do
        local band = overlayOrderBand(entry.order)
        if index > 1 then
            if band ~= previousBand then
                y = y + (region.groupGap or region.gap or 0)
            else
                y = y + (region.gap or 0)
            end
        end

        place(entry, {
            Anchor = region.anchor or "right",
            X = x,
            RightOffset = rightOffset,
            Y = y,
            GroupName = region.groupName,
        }, {
            FontSize = region.fontSize,
            Justification = region.justification,
            VerticalJustification = region.verticalJustification,
        })
        y = y + (region.itemHeight or 24)
        previousBand = band
    end
end

-- The row's text args with the column's own justification applied.
local function columnTextArgs(rowTextArgs, column)
    local textArgs = values.deepCopy(rowTextArgs or {})
    local justification = column.justify or textArgs.Justification
    if justification then
        textArgs.Justification = justification
    end
    return textArgs, justification
end

--- Centered rows: lays `visibleColumns` out left to right around the row's X.
--- Calls `place(column, columnLayout, columnTextArgs)`.
function layout.placeCenteredColumns(rowLayout, rowTextArgs, visibleColumns, columnGap, place)
    local totalWidth = 0
    for _, column in ipairs(visibleColumns) do
        totalWidth = totalWidth + column.minWidth
    end
    if #visibleColumns > 1 then
        totalWidth = totalWidth + (#visibleColumns - 1) * columnGap
    end

    local columnX = (rowLayout.X or 0) - (totalWidth / 2)
    for index, column in ipairs(visibleColumns) do
        local textArgs, justification = columnTextArgs(rowTextArgs, column)
        local textX = columnX
        if justification == "Right" then
            textX = textX + column.minWidth
        elseif justification == "Center" then
            textX = textX + (column.minWidth / 2)
        end
        place(column, {
            X = textX,
            Y = rowLayout.Y,
            GroupName = rowLayout.GroupName,
        }, textArgs)

        columnX = columnX + column.minWidth
        if index < #visibleColumns then
            columnX = columnX + columnGap
        end
    end
end

--- Right-anchored rows: layout for one column `trailingWidth` in from the row's right offset.
---@return table columnLayout, table columnTextArgs
function layout.rightColumnLayout(rowLayout, rowTextArgs, column, trailingWidth)
    local textArgs, justification = columnTextArgs(rowTextArgs, column)
    local rightOffset = (rowLayout.RightOffset or 0) + trailingWidth
    if justification == "Left" then
        rightOffset = rightOffset + column.minWidth
    end
    return {
        Y = rowLayout.Y,
        GroupName = rowLayout.GroupName,
        RightOffset = rightOffset,
    }, textArgs
end

return layout
