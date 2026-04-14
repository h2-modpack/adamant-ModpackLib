local internal = AdamantModpackLib_Internal
local shared = internal.shared
local LayoutTypes = shared.LayoutTypes
local libWarn = shared.libWarn
local registry = shared.fieldRegistry
local GetCursorPosXSafe = registry.GetCursorPosXSafe
local GetCursorPosYSafe = registry.GetCursorPosYSafe
local SetCursorPosSafe = registry.SetCursorPosSafe
local GetStyleMetricX = registry.GetStyleMetricX
local NormalizeColor = registry.NormalizeColor
local EstimateStructuredRowAdvanceY = registry.EstimateStructuredRowAdvanceY
local DrawStructuredAt = registry.DrawStructuredAt

LayoutTypes.separator = {
    validate = function(node, prefix)
        if node.label ~= nil and type(node.label) ~= "string" then
            libWarn("%s: separator label must be string", prefix)
        end
    end,
    render = function(imgui, node, drawChild)
        local _ = drawChild
        if node.label and node.label ~= "" then
            imgui.Separator()
            imgui.Text(node.label)
            imgui.Separator()
        else
            imgui.Separator()
        end
        return true
    end,
}

LayoutTypes.group = {
    validate = function(node, prefix)
        if node.label ~= nil and type(node.label) ~= "string" then
            libWarn("%s: group label must be string", prefix)
        end
        if node.collapsible ~= nil and type(node.collapsible) ~= "boolean" then
            libWarn("%s: group collapsible must be boolean", prefix)
        end
        if node.defaultOpen ~= nil and type(node.defaultOpen) ~= "boolean" then
            libWarn("%s: group defaultOpen must be boolean", prefix)
        end
        if node.children ~= nil and type(node.children) ~= "table" then
            libWarn("%s: group children must be a table", prefix)
        end
    end,
    render = function(imgui, node, drawChild)
        local _ = drawChild
        if node.collapsible == true then
            local flags = node.defaultOpen == true and 32 or 0
            return imgui.CollapsingHeader(node.label or "", flags)
        end
        if node.label and node.label ~= "" then
            imgui.Text(node.label)
        end
        return true
    end,
}

local function GetHorizontalTabItemLabel(child)
    if type(child) ~= "table" then
        return nil
    end
    local tabLabel = child.tabLabel
    if type(tabLabel) ~= "string" or tabLabel == "" then
        return nil
    end
    local tabId = child.tabId
    if type(tabId) == "string" and tabId ~= "" then
        return ("%s##%s"):format(tabLabel, tabId)
    end
    return tabLabel
end

local function ValidateTabbedChildren(node, prefix, layoutName)
    if node.children ~= nil and type(node.children) ~= "table" then
        libWarn("%s: %s children must be a table", prefix, layoutName)
        return false
    end
    if type(node.children) == "table" then
        for childIndex, child in ipairs(node.children) do
            local childPrefix = ("%s child #%d"):format(prefix, childIndex)
            if type(child) ~= "table" then
                libWarn("%s must be a table", childPrefix)
            else
                if type(child.tabLabel) ~= "string" or child.tabLabel == "" then
                    libWarn("%s: %s child tabLabel must be a non-empty string", childPrefix, layoutName)
                end
                if child.tabId ~= nil and (type(child.tabId) ~= "string" or child.tabId == "") then
                    libWarn("%s: %s child tabId must be a non-empty string", childPrefix, layoutName)
                end
                child._tabLabelColor = nil
                if child.tabLabelColor ~= nil then
                    local normalized = NormalizeColor(child.tabLabelColor)
                    if normalized == nil then
                        libWarn("%s: %s child tabLabelColor must be a 3- or 4-number color table", childPrefix, layoutName)
                    else
                        child._tabLabelColor = normalized
                    end
                end
            end
        end
    end
    return true
end

local function WithTabLabelColor(imgui, child, drawFn)
    local color = type(child) == "table" and child._tabLabelColor or nil
    if type(color) ~= "table" then
        return drawFn()
    end

    local textEnum = imgui.ImGuiCol and imgui.ImGuiCol.Text or 0
    imgui.PushStyleColor(textEnum, color[1], color[2], color[3], color[4])
    local ok, a, b, c, d = pcall(drawFn)
    imgui.PopStyleColor()
    if not ok then
        error(a)
    end
    return a, b, c, d
end

local function GetTabbedChildKey(child, index)
    if type(child) ~= "table" then
        return tostring(index)
    end
    if type(child.tabId) == "string" and child.tabId ~= "" then
        return child.tabId
    end
    if type(child.tabLabel) == "string" and child.tabLabel ~= "" then
        return child.tabLabel
    end
    return tostring(index)
end

local function FindTabbedChildByKey(children, activeKey)
    if type(children) ~= "table" or #children == 0 then
        return nil
    end
    for index, child in ipairs(children) do
        if GetTabbedChildKey(child, index) == activeKey then
            return child, index
        end
    end
    return children[1], 1
end

LayoutTypes.horizontalTabs = {
    handlesChildren = true,
    binds = {
        activeTab = { storageType = "string", optional = true },
    },
    validate = function(node, prefix)
        if type(node.id) ~= "string" or node.id == "" then
            libWarn("%s: horizontalTabs id must be a non-empty string", prefix)
        end
        ValidateTabbedChildren(node, prefix, "horizontalTabs")
    end,
    render = function(imgui, node, drawChild, _, bound)
        local changed = false
        local children = type(node.children) == "table" and node.children or {}
        local requestedKey = bound and bound.activeTab and bound.activeTab.get and bound.activeTab:get() or nil
        local activeChild, activeIndex = FindTabbedChildByKey(children, requestedKey or node._activeTabKey)
        node._activeTabKey = GetTabbedChildKey(activeChild, activeIndex)
        if bound and bound.activeTab and bound.activeTab.get and bound.activeTab.set then
            local currentBound = bound.activeTab:get()
            if currentBound ~= node._activeTabKey then
                bound.activeTab:set(node._activeTabKey)
            end
        end

        if imgui.BeginTabBar(node.id) then
            for index, child in ipairs(children) do
                local tabItemLabel = GetHorizontalTabItemLabel(child)
                local opened = false
                if tabItemLabel ~= nil then
                    opened = WithTabLabelColor(imgui, child, function()
                        return imgui.BeginTabItem(tabItemLabel)
                    end)
                end
                if opened then
                    node._activeTabKey = GetTabbedChildKey(child, index)
                    if bound and bound.activeTab and bound.activeTab.get and bound.activeTab.set then
                        local currentBound = bound.activeTab:get()
                        if currentBound ~= node._activeTabKey then
                            bound.activeTab:set(node._activeTabKey)
                        end
                    end
                    if drawChild(child) then
                        changed = true
                    end
                    imgui.EndTabItem()
                end
            end
            imgui.EndTabBar()
        end

        return true, changed
    end,
}

LayoutTypes.verticalTabs = {
    handlesChildren = true,
    binds = {
        activeTab = { storageType = "string", optional = true },
    },
    validate = function(node, prefix)
        if type(node.id) ~= "string" or node.id == "" then
            libWarn("%s: verticalTabs id must be a non-empty string", prefix)
        end
        if node.sidebarWidth ~= nil and (type(node.sidebarWidth) ~= "number" or node.sidebarWidth <= 0) then
            libWarn("%s: verticalTabs sidebarWidth must be a positive number", prefix)
        end
        ValidateTabbedChildren(node, prefix, "verticalTabs")
    end,
    render = function(imgui, node, drawChild, _, bound)
        local children = type(node.children) == "table" and node.children or {}
        if #children == 0 then
            return true, false
        end

        local requestedKey = bound and bound.activeTab and bound.activeTab.get and bound.activeTab:get() or nil
        local activeChild, activeIndex = FindTabbedChildByKey(children, requestedKey or node._activeTabKey)
        node._activeTabKey = GetTabbedChildKey(activeChild, activeIndex)
        if bound and bound.activeTab and bound.activeTab.get and bound.activeTab.set then
            local currentBound = bound.activeTab:get()
            if currentBound ~= node._activeTabKey then
                bound.activeTab:set(node._activeTabKey)
            end
        end

        local changed = false
        local sidebarWidth = node.sidebarWidth or 180
        local gap = GetStyleMetricX(imgui.GetStyle(), "ItemSpacing", 8)
        local originX = GetCursorPosXSafe(imgui)
        local originY = GetCursorPosYSafe(imgui)

        local _, _, sidebarEndY, sidebarHeight = DrawStructuredAt(
            imgui,
            originX,
            originY,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                imgui.BeginChild(node.id .. "##tabs", sidebarWidth, 0, true)
                for index, child in ipairs(children) do
                    local childKey = GetTabbedChildKey(child, index)
                    local selected = WithTabLabelColor(imgui, child, function()
                        return imgui.Selectable(child.tabLabel, childKey == node._activeTabKey)
                    end)
                    if selected then
                        node._activeTabKey = childKey
                        if bound and bound.activeTab and bound.activeTab.get and bound.activeTab.set then
                            local currentBound = bound.activeTab:get()
                            if currentBound ~= node._activeTabKey then
                                bound.activeTab:set(node._activeTabKey)
                            end
                        end
                    end
                end
                imgui.EndChild()
                return false
            end)

        local activeChildChanged, _, detailEndY, detailHeight = DrawStructuredAt(
            imgui,
            originX + sidebarWidth + gap,
            originY,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                imgui.BeginChild(node.id .. "##detail", 0, 0, true)
                activeChild = select(1, FindTabbedChildByKey(children, node._activeTabKey))
                local childChanged = false
                if activeChild ~= nil and drawChild(activeChild) then
                    childChanged = true
                end
                imgui.EndChild()
                return childChanged
            end)
        changed = activeChildChanged or changed

        local finalY = originY + math.max(sidebarHeight or 0, detailHeight or 0)
        if type(sidebarEndY) == "number" and sidebarEndY > finalY then
            finalY = sidebarEndY
        end
        if type(detailEndY) == "number" and detailEndY > finalY then
            finalY = detailEndY
        end
        SetCursorPosSafe(imgui, originX, finalY)

        return true, changed
    end,
}

local function ValidatePanelColumn(prefix, index, column, seenNames)
    local columnPrefix = ("%s columns[%d]"):format(prefix, index)
    if type(column) ~= "table" then
        libWarn("%s must be a table", columnPrefix)
        return
    end
    if column.name ~= nil then
        if type(column.name) ~= "string" or column.name == "" then
            libWarn("%s.name must be a non-empty string", columnPrefix)
        elseif seenNames[column.name] then
            libWarn("%s: duplicate column name '%s'", prefix, tostring(column.name))
        else
            seenNames[column.name] = true
        end
    end
    if column.start ~= nil then
        if type(column.start) ~= "number" then
            libWarn("%s.start must be a number", columnPrefix)
        elseif column.start < 0 then
            libWarn("%s.start must be a non-negative number", columnPrefix)
        end
    end
    if column.width ~= nil and (type(column.width) ~= "number" or column.width <= 0) then
        libWarn("%s.width must be a positive number", columnPrefix)
    end
    if column.align ~= nil and column.align ~= "center" and column.align ~= "right" then
        libWarn("%s.align must be one of 'center' or 'right'", columnPrefix)
    end
end

local function ResolvePanelColumn(node, columnRef)
    if type(node.columns) ~= "table" then
        return nil
    end
    if type(columnRef) == "number" then
        return node.columns[columnRef]
    end
    if type(columnRef) == "string" and columnRef ~= "" then
        for _, column in ipairs(node.columns) do
            if type(column) == "table" and column.name == columnRef then
                return column
            end
        end
    end
    return nil
end

local function GetPanelChildKey(child)
    local placement = type(child) == "table" and child.panel or nil
    local childKey = type(placement) == "table" and placement.key or nil
    if type(childKey) == "string" and childKey ~= "" then
        return childKey
    end
    return nil
end

local function ValidatePanelChild(node, prefix, childIndex, child, seenKeys)
    if type(child) ~= "table" then
        return
    end
    local placement = child.panel
    if placement == nil then
        return
    end
    local placementPrefix = ("%s child #%d panel"):format(prefix, childIndex)
    if type(placement) ~= "table" then
        libWarn("%s must be a table", placementPrefix)
        return
    end
    if placement.column == nil then
        libWarn("%s.column is required", placementPrefix)
    elseif ResolvePanelColumn(node, placement.column) == nil then
        libWarn("%s.column references unknown column '%s'", placementPrefix, tostring(placement.column))
    end
    if placement.line ~= nil then
        if type(placement.line) ~= "number" or placement.line < 1 or math.floor(placement.line) ~= placement.line then
            libWarn("%s.line must be a positive integer", placementPrefix)
        end
    end
    if placement.key ~= nil then
        if type(placement.key) ~= "string" or placement.key == "" then
            libWarn("%s.key must be a non-empty string", placementPrefix)
        elseif seenKeys[placement.key] then
            libWarn("%s: duplicate panel child key '%s'", prefix, tostring(placement.key))
        else
            seenKeys[placement.key] = true
        end
    end
end

local function ResolvePanelChildPlacement(node, child, index)
    local placement = type(child) == "table" and child.panel or nil
    local column = type(placement) == "table" and ResolvePanelColumn(node, placement.column) or nil
    return {
        child = child,
        index = index,
        key = GetPanelChildKey(child),
        line = type(placement) == "table" and placement.line or 1,
        start = type(column) == "table" and column.start or nil,
        width = type(column) == "table" and column.width or nil,
        align = type(column) == "table" and column.align or nil,
    }
end

local function BuildPanelEntries(node)
    if type(node) == "table" and type(node._staticPanelEntries) == "table" then
        return node._staticPanelEntries
    end

    local children = type(node.children) == "table" and node.children or {}
    local entries = {}
    local entryCount = 0

    for index, child in ipairs(children) do
        local entry = ResolvePanelChildPlacement(node, child, index)
        entryCount = entryCount + 1
        entries[entryCount] = {
            child = entry.child,
            index = entry.index,
            key = entry.key,
            line = entry.line,
            start = entry.start,
            width = entry.width,
            align = entry.align,
        }
    end

    if type(node) == "table" then
        node._staticPanelEntries = entries
    end

    return entries
end

local function BuildPanelEntryOrderKey(entries)
    local parts = {}
    for _, entry in ipairs(entries) do
        parts[#parts + 1] = tostring(entry.key or entry.index)
        parts[#parts + 1] = "@"
        parts[#parts + 1] = tostring(entry.line or 1)
        parts[#parts + 1] = ":"
        parts[#parts + 1] = entry.start ~= nil and tostring(entry.start) or "_"
        parts[#parts + 1] = "|"
    end
    return table.concat(parts)
end

local function GetOrderedPanelEntries(node, entries)
    local orderKey = BuildPanelEntryOrderKey(entries)
    if type(node) == "table" and node._panelOrderCacheKey == orderKey
        and type(node._panelOrderCacheOrder) == "table" then
        return node._panelOrderCacheOrder
    end

    local orderedPositions = {}
    for index = 1, #entries do
        orderedPositions[index] = index
    end

    table.sort(orderedPositions, function(leftIndex, rightIndex)
        local left = entries[leftIndex]
        local right = entries[rightIndex]
        if left.line ~= right.line then
            return left.line < right.line
        end
        if type(left.start) == "number" and type(right.start) == "number" and left.start ~= right.start then
            return left.start < right.start
        end
        return left.index < right.index
    end)

    if type(node) == "table" then
        node._panelOrderCacheKey = orderKey
        node._panelOrderCacheOrder = orderedPositions
    end
    return orderedPositions
end

local function BuildPanelRows(entries, orderedPositions)
    local rows = {}
    local rowCount = 0
    local currentLine = nil

    for _, position in ipairs(orderedPositions) do
        local entry = entries[position]
        if currentLine ~= entry.line then
            currentLine = entry.line
            rowCount = rowCount + 1
            rows[rowCount] = {
                line = currentLine,
                entries = {},
            }
        end
        local row = rows[rowCount]
        row.entries[#row.entries + 1] = entry
    end

    return rows
end

LayoutTypes.panel = {
    handlesChildren = true,
    validate = function(node, prefix)
        if node.id ~= nil and (type(node.id) ~= "string" or node.id == "") then
            libWarn("%s: panel id must be a non-empty string", prefix)
        end
        if type(node.columns) ~= "table" or #node.columns == 0 then
            libWarn("%s: panel columns must be a non-empty list", prefix)
        else
            local seenNames = {}
            for index, column in ipairs(node.columns) do
                ValidatePanelColumn(prefix, index, column, seenNames)
            end
        end
        if node.children ~= nil and type(node.children) ~= "table" then
            libWarn("%s: panel children must be a table", prefix)
        elseif type(node.children) == "table" then
            local seenKeys = {}
            for childIndex, child in ipairs(node.children) do
                ValidatePanelChild(node, prefix, childIndex, child, seenKeys)
            end
        end
    end,
    render = function(imgui, node, drawChild, uiState)
        local hasPanelId = type(node.id) == "string" and node.id ~= ""
        if hasPanelId then
            imgui.PushID(node.id)
        end

        local rowStartX = GetCursorPosXSafe(imgui)
        local rowStartY = GetCursorPosYSafe(imgui)
        local entries = BuildPanelEntries(node)
        local orderedPositions = GetOrderedPanelEntries(node, entries)
        local rows = BuildPanelRows(entries, orderedPositions)

        local changed = false
        local defaultRowAdvance = EstimateStructuredRowAdvanceY(imgui)
        local renderRows = {}

        for _, row in ipairs(rows) do
            local visibleEntries = {}
            for _, entry in ipairs(row.entries) do
                if public.isUiNodeVisible(entry.child, uiState and uiState.view) then
                    visibleEntries[#visibleEntries + 1] = entry
                end
            end
            if #visibleEntries > 0 then
                renderRows[#renderRows + 1] = {
                    line = row.line,
                    entries = visibleEntries,
                }
            end
        end

        local currentRowY = rowStartY

        for _, row in ipairs(renderRows) do
            local rowAdvance = defaultRowAdvance

            for entryIndex, entry in ipairs(row.entries) do
                if entryIndex > 1 and type(entry.start) ~= "number" then
                    imgui.SameLine()
                end

                local childX = type(entry.start) == "number" and (rowStartX + entry.start) or GetCursorPosXSafe(imgui)
                local childChanged, nextX, _, childAdvance = DrawStructuredAt(
                    imgui,
                    childX,
                    currentRowY,
                    defaultRowAdvance,
                    function()
                        return drawChild(entry.child) == true
                    end)
                if childChanged then
                    changed = true
                end
                if childAdvance > rowAdvance then
                    rowAdvance = childAdvance
                end

                SetCursorPosSafe(imgui, nextX, currentRowY)
            end

            currentRowY = currentRowY + rowAdvance
        end

        SetCursorPosSafe(imgui, rowStartX, currentRowY)

        if hasPanelId then
            imgui.PopID()
        end

        return true, changed
    end,
}

local function DrawLayoutNode(imgui, node, drawChild, layoutTypes, uiState)
    local layoutType = layoutTypes[node.type]
    if not layoutType then
        return false, false
    end
    local bound = nil
    if type(layoutType.binds) == "table" then
        bound = node._boundCache
        if bound == nil or node._boundCacheUiState ~= uiState or node._boundCacheBindOwnerType ~= layoutType then
            bound = shared.fieldRegistry.BuildBoundEntries(node, layoutType, uiState)
        end
        bound._changed = false
    end
    -- Layout render contract:
    --   open = render(imgui, node, drawChild)
    --   or, when layoutType.handlesChildren == true:
    --   open, changed = render(imgui, node, drawChild)
    -- Layouts with handlesChildren = true fully own child rendering and must
    -- report any child-driven change via the second return value.
    local open, layoutChanged = layoutType.render(imgui, node, drawChild, uiState, bound)
    if layoutType.handlesChildren == true then
        return true, (bound and bound._changed or false) or layoutChanged == true
    end
    local changed = false
    if open and type(node.children) == "table" then
        for _, child in ipairs(node.children) do
            if drawChild(child) then changed = true end
        end
    end
    return true, (bound and bound._changed or false) or changed
end

registry.DrawLayoutNode = DrawLayoutNode
