local deps = ...

-- Overlay entry registry and refresh orchestration: text and stack-row entries, visibility
-- policy, and the game hooks that re-evaluate visibility.
local rendererState = deps.state
local isUiSuppressed = deps.isUiSuppressed
local values = deps.values
local overlayOrder = deps.order
local rendererSystem = deps.system
local overlayGameDeps = deps.gameDeps
local overlayLayout = deps.layout
local hudComponents = deps.hudComponents
local victoryStamp = deps.victoryStamp

local REGIONS = overlayLayout.REGIONS
local VICTORY_REGION = overlayLayout.VICTORY_REGION

local refreshStackRows

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

local function isVictoryStampEligible()
    if not victoryStamp.isScreenOpen() or isUiSuppressed() then
        return false
    end
    for _, entry in pairs(rendererState.textElements) do
        if entry.isStamp and isEntryVisible(entry) then
            return true
        end
    end
    return false
end

local function isVisible(entry)
    if isUiSuppressed() or not isEntryVisible(entry) then
        return false
    end
    if entry.region == VICTORY_REGION then
        return isVictoryStampEligible()
    end
    return (entry.hudVisibility == "independent" or isGameHudVisible())
        and not victoryStamp.isScreenOpen()
end

local function resolveText(entry)
    return tostring(resolveValue(entry.text) or "")
end

local function readColumnVisible(rowVisible, column, opts)
    if rowVisible == false then
        return false
    end
    if opts and opts.useCachedVisible == true and column.layoutVisible ~= nil then
        return column.layoutVisible
    end
    local visible = resolveValue(column.visible) ~= false
    column.layoutVisible = visible
    return visible
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
    return hudComponents.sanitizeName(baseName .. "." .. tostring(suffix))
end

local function stackRowElementId(region, id)
    return "stack:" .. tostring(region) .. ":" .. tostring(id)
end

local function refreshVictoryStamp()
    if victoryStamp.sync(isVictoryStampEligible()) then
        refreshStackRows(VICTORY_REGION)
    end
end

local function applyVisibility(entry, component, force)
    refreshVictoryStamp()
    local nextVisible = isVisible(entry)
    if not force and nextVisible == entry.displayedVisible then
        return
    end

    overlayGameDeps.SetAlpha({ Id = component.Id, Fraction = nextVisible and 1.0 or 0.0, Duration = 0.0 })
    entry.displayedVisible = nextVisible
end

local function updateText(entry, force)
    local component = hudComponents.ensure(entry)
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
    local component = hudComponents.ensure(entry)
    if not component then
        return
    end

    applyVisibility(entry, component, force)
end

local function readLayoutVisible(entry, opts)
    if opts and opts.useCachedVisible == true and entry.layoutVisible ~= nil then
        return entry.layoutVisible
    end
    local visible = isEntryVisible(entry)
    entry.layoutVisible = visible
    return visible
end

local function getRegionEntries(regionName, opts)
    local entries = {}
    for _, entry in pairs(rendererState.stackRows) do
        if entry.region == regionName and readLayoutVisible(entry, opts) then
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

local function layoutRegion(regionName, opts)
    local recomputeEntries = opts and opts.recomputeEntries or nil
    local entries = getRegionEntries(regionName, opts)
    overlayLayout.placeRows(REGIONS[regionName], entries, function(entry, rowLayout, rowTextArgs)
        local layoutOpts = nil
        if opts
            and opts.useCachedVisible == true
            and opts.recomputeEntry ~= entry
            and not (recomputeEntries and recomputeEntries[entry] == true)
        then
            layoutOpts = {
                useCachedVisible = true,
            }
        end
        entry.setLayout(rowLayout, rowTextArgs, layoutOpts)
    end)
end

local function refreshStackRowEntry(entry, layoutAlreadyRefreshed, opts)
    if layoutAlreadyRefreshed ~= true then
        layoutRegion(entry.region, opts)
    end
    local visible = readLayoutVisible(entry, opts)
    entry.setVisible(visible)
    entry.refreshText(visible)
end

local function refreshOwnedStackRowEntry(entry)
    entry.layoutVisible = isEntryVisible(entry)
    layoutRegion(entry.region, {
        recomputeEntry = entry,
        useCachedVisible = true,
    })
    refreshStackRowEntry(entry, true, {
        useCachedVisible = true,
    })
end

-- Re-lays out the regions the given stack-row handles occupy, re-evaluating only their
-- entries' visibility (siblings keep their cached layout visibility).
local function refreshOwnedStackRowHandles(handles)
    local entries = {}
    local regionNames = {}
    local regions = {}
    local recomputeEntries = {}
    for _, handle in ipairs(handles) do
        local entry = handle.__stackRowEntry
        if recomputeEntries[entry] ~= true then
            entries[#entries + 1] = entry
            entry.layoutVisible = isEntryVisible(entry)
            recomputeEntries[entry] = true
            if regions[entry.region] ~= true then
                regions[entry.region] = true
                regionNames[#regionNames + 1] = entry.region
            end
        end
    end

    for _, regionName in ipairs(regionNames) do
        layoutRegion(regionName, {
            recomputeEntries = recomputeEntries,
            useCachedVisible = true,
        })
    end

    for _, entry in ipairs(entries) do
        refreshStackRowEntry(entry, true, {
            useCachedVisible = true,
        })
    end
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
    refreshVictoryStamp()
end

-- Import-local on purpose: a Lib re-import redefines the hooks once, and the system
-- hook define replaces the previous import's install for the renderer owner.
local gameHooksDefined = false

local function ensureGameHooks()
    if gameHooksDefined then
        return
    end
    rendererSystem.hooks.define(function(hooks)
        hooks.wrap("OnScreenOpened", "victoryOpened", function(base, screen, args)
            base(screen, args)
            if screen.Name == "RunClear" then
                refreshAll()
            end
        end)
        hooks.wrap("OnScreenCloseFinished", "victoryClosed", function(base, screen, args)
            base(screen, args)
            if screen.Name == "RunClear" then
                refreshAll()
            end
        end)
        hooks.wrap("StartRoomPresentation", "roomPresentation", function(base, currentRun, currentRoom, metaPointsAwarded)
            base(currentRun, currentRoom, metaPointsAwarded)
            refreshAll()
        end)
        hooks.wrap("ShowCombatUI", "showCombatUI", function(base, flag, args)
            base(flag, args)
            refreshAll()
        end)
        hooks.wrap("HideCombatUI", "hideCombatUI", function(base, flag, args)
            base(flag, args)
            refreshAll()
        end)
    end)
    gameHooksDefined = true
end

-- One HUD text component backing a stack-row column. It stays hidden and component-less
-- until its row lays it out.
local function createTextElement(opts)
    local id = opts.id
    local entry = {
        id = id,
        componentName = opts.componentName,
        layout = {},
        textArgs = opts.textArgs,
        text = opts.text or "",
        visible = false,
        hudVisibility = opts.hudVisibility,
        region = opts.region,
        isStamp = opts.isStamp,
        displayedText = nil,
        deferHiddenComponentCreation = true,
        deferUntilLayout = true,
    }

    rendererState.textElements[id] = entry
    hudComponents.ensureData(entry)
    ensureGameHooks()

    -- Handles look the entry up by id so calls after unregister are no-ops.
    return {
        setText = function(text)
            local current = rendererState.textElements[id]
            if not current then return end
            current.text = text
            updateText(current)
        end,
        setVisible = function(visible)
            local current = rendererState.textElements[id]
            if not current then return end
            current.visible = visible == true
            if current.deferHiddenComponentCreation == true
                and not isEntryVisible(current)
                and current.displayedText == nil
            then
                return
            end
            updateVisibility(current)
        end,
        setLayout = function(layout, textArgs)
            local current = rendererState.textElements[id]
            if not current then return end
            local nextSignature = hudComponents.layoutSignature(layout)
            if current.layoutSignature ~= nextSignature or current.componentLayoutSignature ~= nextSignature then
                hudComponents.discard(current)
            end
            current.layout = layout
            current.layoutSignature = nextSignature
            for key, value in pairs(textArgs or {}) do
                current.textArgs[key] = value
            end
            hudComponents.ensureData(current)
        end,
        unregister = function()
            local current = rendererState.textElements[id]
            if not current then return end
            current.visible = false
            updateVisibility(current)
            hudComponents.discard(current)
            rendererState.textElements[id] = nil
        end,
    }
end

--- Registers one stack row in a managed region. Specs arrive validated by overlay declarations.
local function createStackRow(opts)
    local region = opts.region or "middleRightStack"
    local componentBase = opts.componentName or opts.id
    local columnGap = tonumber(opts.columnGap) or 6
    local columns = {}
    for index, column in ipairs(opts.columns) do
        columns[#columns + 1] = {
            key = column.key or tostring(index),
            minWidth = tonumber(column.minWidth) or 0,
            justify = column.justify,
            text = column.text or "",
            visible = column.visible,
            handle = createTextElement({
                id = stackRowElementId(region, opts.id .. ":" .. tostring(column.key or index)),
                componentName = column.componentName or columnComponentName(componentBase, column, index),
                textArgs = sanitizeStackRowTextArgs(column.textArgs),
                text = column.text,
                hudVisibility = opts.hudVisibility,
                region = region,
                isStamp = opts.isStamp == true,
            }),
        }
    end

    local function placeColumn(column, columnLayout, columnTextArgs)
        column.handle.setLayout(columnLayout, columnTextArgs)
    end

    local entry = {
        id = opts.id,
        region = region,
        order = tonumber(opts.order) or overlayOrder.module,
        visible = opts.visible,
        columns = columns,
        setLayout = function(rowLayout, rowTextArgs, layoutOpts)
            if rowLayout.Anchor == "center" then
                local visibleColumns = {}
                for _, column in ipairs(columns) do
                    if readColumnVisible(true, column, layoutOpts) then
                        visibleColumns[#visibleColumns + 1] = column
                    else
                        column.handle.setVisible(false)
                    end
                end
                overlayLayout.placeCenteredColumns(rowLayout, rowTextArgs, visibleColumns, columnGap, placeColumn)
                return
            end

            local trailingWidth = 0
            for index = #columns, 1, -1 do
                local column = columns[index]
                if readColumnVisible(true, column, layoutOpts) then
                    placeColumn(column, overlayLayout.rightColumnLayout(rowLayout, rowTextArgs, column, trailingWidth))
                    trailingWidth = trailingWidth + column.minWidth
                    if index > 1 then
                        trailingWidth = trailingWidth + columnGap
                    end
                else
                    column.handle.setVisible(false)
                end
            end
        end,
        setVisible = function(visible)
            for _, column in ipairs(columns) do
                column.handle.setVisible(readColumnVisible(visible, column))
            end
        end,
        refreshText = function(visible)
            if not visible then return end
            for _, column in ipairs(columns) do
                if readColumnVisible(true, column) then
                    column.handle.setText(column.text)
                end
            end
        end,
    }

    local key = region .. "\0" .. opts.id
    rendererState.stackRows[key] = entry
    refreshStackRowEntry(entry)

    return {
        __stackRowEntry = entry,
        refreshOwned = function()
            refreshOwnedStackRowEntry(entry)
        end,
        unregister = function()
            rendererState.stackRows[key] = nil
            for _, column in ipairs(columns) do
                column.handle.unregister()
            end
            refreshStackRows(region)
        end,
    }
end

return {
    refreshTextElements = refreshTextElements,
    refreshStackRows = refreshStackRows,
    refreshAll = refreshAll,
    refreshOwnedStackRowHandles = refreshOwnedStackRowHandles,
    createStackRow = createStackRow,
}
