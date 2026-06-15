local deps = ...

local rendererState = deps.state
local isUiSuppressed = deps.isUiSuppressed
local logging = deps.logging
local values = deps.values
local overlayOrder = deps.order
local rendererSystem = deps.system
local overlayGameDeps = deps.gameDeps

local refreshStackRows

local REGIONS = {
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
}

local DEFAULT_TEXT_ARGS = {
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
}

local function sanitizeComponentName(id)
    return "AdamantOverlay_" .. tostring(id):gsub("[^%w_%-]", "_")
end

local function resolveValue(value)
    if type(value) == "function" then
        return value()
    end
    return value
end

local function isEntryVisible(entry)
    local visible = resolveValue(entry.visible)
    return visible ~= false
end

local function isGameHudVisible()
    return overlayGameDeps.ShowingCombatUI() == true
end

local function isVisible(entry)
    return isGameHudVisible() and not isUiSuppressed() and isEntryVisible(entry)
end

local function resolveText(entry)
    return tostring(resolveValue(entry.text) or "")
end

local function isColumnVisible(rowVisible, column)
    if rowVisible == false then
        return false
    end
    local visible = resolveValue(column.visible)
    return visible ~= false
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

local function sanitizeStackRowTextArgs(textArgs)
    local sanitized = values.deepCopy(textArgs or {})
    sanitized.FontSize = nil
    sanitized.Justification = nil
    sanitized.VerticalJustification = nil
    sanitized.OffsetX = nil
    sanitized.OffsetY = nil
    return sanitized
end

local function columnComponentName(baseName, column, index)
    local suffix = column.key or index
    return sanitizeComponentName(baseName .. "." .. tostring(suffix))
end

local function stackRowElementId(region, id)
    return "stack:" .. tostring(region) .. ":" .. tostring(id)
end

local function layoutSignature(layout)
    layout = layout or {}
    return table.concat({
        tostring(layout.Anchor),
        tostring(layout.X),
        tostring(layout.Y),
        tostring(layout.RightOffset),
        tostring(layout.BottomOffset),
    }, "|")
end

local function ensureComponentData(entry)
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

local function discardExistingComponent(entry)
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

local function ensureComponent(entry)
    if entry.deferUntilLayout == true and entry.layoutSignature == nil then
        ensureComponentData(entry)
        return nil
    end

    ensureComponentData(entry)

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
                entry.componentLayoutSignature = layoutSignature(entry.layout)
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
        entry.componentLayoutSignature = entry.componentLayoutSignature or layoutSignature(entry.layout)
    end

    return component
end

local function applyVisibility(entry, component, force)
    local nextVisible = isVisible(entry)
    if not force and nextVisible == entry.displayedVisible then
        return
    end

    overlayGameDeps.SetAlpha({ Id = component.Id, Fraction = nextVisible and 1.0 or 0.0, Duration = 0.0 })
    entry.displayedVisible = nextVisible
end

local function updateText(entry, force)
    local component = ensureComponent(entry)
    if not component then
        return
    end

    local nextText = resolveText(entry)
    if not force and nextText == entry.displayedText then
        return
    end

    overlayGameDeps.ModifyTextBox({ Id = component.Id, Text = nextText })
    entry.displayedText = nextText
    if not isVisible(entry) then
        applyVisibility(entry, component, true)
    end
end

local function updateVisibility(entry, force)
    local component = ensureComponent(entry)
    if not component then
        return
    end

    applyVisibility(entry, component, force)
end

local function updateEntry(entry)
    updateText(entry)
    updateVisibility(entry)
end

local function getRegionEntries(regionName)
    local entries = {}
    for _, entry in pairs(rendererState.stackRows) do
        if entry.region == regionName and isEntryVisible(entry) then
            entries[#entries + 1] = entry
        end
    end
    table.sort(entries, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.id < b.id
    end)
    return entries
end

local function layoutRegion(regionName)
    local region = REGIONS[regionName]
    if not region then
        return
    end

    local entries = getRegionEntries(regionName)
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

        local layout = {
            Anchor = region.anchor or "right",
            X = x,
            RightOffset = rightOffset,
            Y = y,
        }
        entry.setLayout(layout, {
            FontSize = region.fontSize,
            Justification = region.justification,
            VerticalJustification = region.verticalJustification,
        })
        y = y + (region.itemHeight or 24)
        previousBand = band
    end
end

local function refreshStackRowEntry(entry, layoutAlreadyRefreshed)
    if layoutAlreadyRefreshed ~= true then
        layoutRegion(entry.region)
    end
    local visible = isEntryVisible(entry)
    entry.setVisible(visible)
    entry.refreshText(visible)
end

local function unregisterStackRowEntry(region, key, unregisterComponents)
    rendererState.stackRows[key] = nil
    unregisterComponents()
    refreshStackRows(region)
end

local function refreshTextElements(forceVisibility)
    for _, entry in pairs(rendererState.textElements) do
        updateText(entry, forceVisibility == true)
        updateVisibility(entry, forceVisibility == true)
    end
end

function refreshStackRows(regionName)
    if regionName ~= nil then
        layoutRegion(regionName)
        for _, entry in pairs(rendererState.stackRows) do
            if entry.region == regionName then
                refreshStackRowEntry(entry, true)
            end
        end
        return
    end

    local laidOutRegions = {}
    for _, entry in pairs(rendererState.stackRows) do
        if not laidOutRegions[entry.region] then
            layoutRegion(entry.region)
            laidOutRegions[entry.region] = true
        end
        refreshStackRowEntry(entry, true)
    end
end

local function refreshAll()
    refreshStackRows()
    refreshTextElements(true)
end

local function refreshVisibility()
    refreshAll()
end

local function ensureGameHooks()
    rendererSystem.hooks.define(function(hooks)
        hooks.wrap("StartRoomPresentation", "roomPresentation", function(base, currentRun, currentRoom, metaPointsAwarded)
            base(currentRun, currentRoom, metaPointsAwarded)
            refreshVisibility()
        end)
        hooks.wrap("ShowCombatUI", "showCombatUI", function(base, flag, args)
            base(flag, args)
            refreshVisibility()
        end)
        hooks.wrap("HideCombatUI", "hideCombatUI", function(base, flag, args)
            base(flag, args)
            refreshVisibility()
        end)
    end)
end

local function makeTextHandle(id)
    return {
        setText = function(text)
            local entry = rendererState.textElements[id]
            if not entry then return end
            entry.text = text
            updateText(entry)
        end,
        setVisible = function(visible)
            local entry = rendererState.textElements[id]
            if not entry then return end
            if type(visible) == "function" then
                entry.visible = visible
            else
                entry.visible = visible == true
            end
            if entry.deferHiddenComponentCreation == true and not isEntryVisible(entry) and entry.displayedText == nil then
                return
            end
            updateVisibility(entry)
        end,
        setLayout = function(layout, textArgs)
            local entry = rendererState.textElements[id]
            if not entry then return end
            local nextLayout = layout or {}
            local nextSignature = layoutSignature(nextLayout)
            if entry.layoutSignature ~= nextSignature or entry.componentLayoutSignature ~= nextSignature then
                discardExistingComponent(entry)
            end
            entry.layout = nextLayout
            entry.layoutSignature = nextSignature
            for key, value in pairs(textArgs or {}) do
                entry.textArgs[key] = value
            end
            ensureComponentData(entry)
        end,
        refresh = function()
            local entry = rendererState.textElements[id]
            if not entry then return end
            updateEntry(entry)
        end,
        unregister = function()
            local entry = rendererState.textElements[id]
            if not entry then return end
            entry.visible = false
            updateVisibility(entry)
            discardExistingComponent(entry)
            rendererState.textElements[id] = nil
        end,
    }
end

local function createTextElement(opts)
    if type(opts) ~= "table" then
        logging.violate("overlays.invalid_registration", "overlay renderer: hud text opts must be a table")
    end
    if type(opts.id) ~= "string" or opts.id == "" then
        logging.violate("overlays.invalid_registration", "overlay renderer: hud text id must be a non-empty string")
    end

    local entry = {
        id = opts.id,
        componentName = opts.componentName or sanitizeComponentName(opts.id),
        layout = opts.layout or {},
        textArgs = opts.textArgs or {},
        text = opts.text or "",
        visible = opts.visible,
        displayedText = nil,
        deferHiddenComponentCreation = opts.deferHiddenComponentCreation == true,
        deferUntilLayout = opts.deferUntilLayout == true,
    }

    rendererState.textElements[opts.id] = entry
    ensureComponentData(entry)
    ensureGameHooks()
    if opts.deferInitialUpdate ~= true then
        updateEntry(entry)
    end

    return makeTextHandle(opts.id)
end

local function createStackRow(opts)
    if type(opts) ~= "table" then
        logging.violate("overlays.invalid_registration", "overlay renderer: stacked row opts must be a table")
    end
    if type(opts.id) ~= "string" or opts.id == "" then
        logging.violate("overlays.invalid_registration", "overlay renderer: stacked row id must be a non-empty string")
    end
    if type(opts.columns) ~= "table" or #opts.columns == 0 then
        logging.violate("overlays.invalid_registration", "overlay renderer: stacked row columns must be a non-empty array")
    end

    local region = opts.region or "middleRightStack"
    if REGIONS[region] == nil then
        logging.violate(
            "overlays.invalid_registration",
            "overlay renderer: unknown stacked region '%s'",
            tostring(region)
        )
    end

    local componentBase = opts.componentName or opts.id
    local columnGap = tonumber(opts.columnGap) or 6
    local columns = {}
    for index, column in ipairs(opts.columns) do
        if type(column) ~= "table" then
            logging.violate(
                "overlays.invalid_registration",
                "overlay renderer: stacked row column #%d must be a table",
                index
            )
        end
        local columnEntry = {
            key = column.key or tostring(index),
            minWidth = tonumber(column.minWidth) or 0,
            justify = column.justify,
            text = column.text or "",
            visible = column.visible,
            handle = createTextElement({
                id = stackRowElementId(region, opts.id .. ":" .. tostring(column.key or index)),
                componentName = column.componentName or columnComponentName(componentBase, column, index),
                layout = {},
                textArgs = sanitizeStackRowTextArgs(column.textArgs),
                text = column.text,
                visible = false,
                deferInitialUpdate = true,
                deferHiddenComponentCreation = true,
                deferUntilLayout = true,
            }),
        }
        columns[#columns + 1] = columnEntry
    end

    local entry = {
        id = opts.id,
        region = region,
        order = tonumber(opts.order) or overlayOrder.module,
        visible = opts.visible,
        columns = columns,
        setLayout = function(layout, textArgs)
            if layout.Anchor == "center" then
                local visibleColumns = {}
                local totalWidth = 0
                for _, column in ipairs(columns) do
                    if isColumnVisible(true, column) then
                        visibleColumns[#visibleColumns + 1] = column
                        totalWidth = totalWidth + column.minWidth
                    else
                        column.handle.setVisible(false)
                    end
                end
                if #visibleColumns > 1 then
                    totalWidth = totalWidth + (#visibleColumns - 1) * columnGap
                end

                local columnX = (layout.X or 0) - (totalWidth / 2)
                for index, column in ipairs(visibleColumns) do
                    local columnTextArgs = values.deepCopy(textArgs or {})
                    local justification = column.justify or columnTextArgs.Justification
                    if justification then
                        columnTextArgs.Justification = justification
                    end

                    local textX = columnX
                    if justification == "Right" then
                        textX = textX + column.minWidth
                    elseif justification == "Center" then
                        textX = textX + (column.minWidth / 2)
                    end
                    column.handle.setLayout({
                        X = textX,
                        Y = layout.Y,
                    }, columnTextArgs)

                    columnX = columnX + column.minWidth
                    if index < #visibleColumns then
                        columnX = columnX + columnGap
                    end
                end
                return
            end

            local trailingWidth = 0
            for index = #columns, 1, -1 do
                local column = columns[index]
                if not isColumnVisible(true, column) then
                    column.handle.setVisible(false)
                    goto continue
                end
                local columnTextArgs = values.deepCopy(textArgs or {})
                local justification = column.justify or columnTextArgs.Justification
                if justification then
                    columnTextArgs.Justification = justification
                end
                local columnLayout = {
                    Y = layout.Y,
                }
                local rightOffset = (layout.RightOffset or 0) + trailingWidth
                if justification == "Left" then
                    rightOffset = rightOffset + column.minWidth
                end
                columnLayout.RightOffset = rightOffset
                column.handle.setLayout(columnLayout, columnTextArgs)
                trailingWidth = trailingWidth + column.minWidth
                if index > 1 then
                    trailingWidth = trailingWidth + columnGap
                end
                ::continue::
            end
        end,
        setVisible = function(visible)
            for _, column in ipairs(columns) do
                column.handle.setVisible(isColumnVisible(visible, column))
            end
        end,
        refreshText = function(visible)
            if not visible then return end
            for _, column in ipairs(columns) do
                if isColumnVisible(true, column) then
                    column.handle.setText(column.text)
                end
            end
        end,
    }

    local key = region .. "\0" .. opts.id
    rendererState.stackRows[key] = entry
    refreshStackRowEntry(entry)

    return {
        setColumnText = function(columnKey, text)
            for _, column in ipairs(columns) do
                if column.key == columnKey then
                    column.text = text
                    refreshStackRowEntry(entry)
                    return true
                end
            end
            return false
        end,
        setVisible = function(visible)
            if type(visible) == "function" then
                entry.visible = visible
            else
                entry.visible = visible == true
            end
            refreshStackRowEntry(entry)
        end,
        refresh = function()
            refreshStackRowEntry(entry)
        end,
        refreshText = function()
            entry.refreshText(isEntryVisible(entry))
        end,
        unregister = function()
            unregisterStackRowEntry(region, key, function()
                for _, column in ipairs(columns) do
                    column.handle.unregister()
                end
            end)
        end,
    }
end

return {
    refreshTextElements = refreshTextElements,
    refreshStackRows = refreshStackRows,
    refreshAll = refreshAll,
    refreshVisibility = refreshVisibility,
    ensureGameHooks = ensureGameHooks,
    makeTextHandle = makeTextHandle,
    createTextElement = createTextElement,
    createStackRow = createStackRow,
}
