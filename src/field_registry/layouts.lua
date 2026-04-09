local internal = AdamantModpackLib_Internal
local shared = internal.shared
local LayoutTypes = shared.LayoutTypes
local libWarn = shared.libWarn
local registry = shared.fieldRegistry
local GetCursorPosXSafe = registry.GetCursorPosXSafe

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

local function ValidatePanelChild(node, prefix, childIndex, child)
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
    if placement.slots ~= nil then
        if type(placement.slots) ~= "table" then
            libWarn("%s.slots must be a list of slot names", placementPrefix)
        else
            for slotIndex, slotName in ipairs(placement.slots) do
                if type(slotName) ~= "string" or slotName == "" then
                    libWarn("%s.slots[%d] must be a non-empty string", placementPrefix, slotIndex)
                end
            end
        end
    end
end

LayoutTypes.panel = {
    handlesChildren = true,
    validate = function(node, prefix)
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
            for childIndex, child in ipairs(node.children) do
                ValidatePanelChild(node, prefix, childIndex, child)
            end
        end
    end,
    render = function(imgui, node, drawChild)
        local children = type(node.children) == "table" and node.children or {}
        local rowStart = GetCursorPosXSafe(imgui)
        local entries = {}

        for index, child in ipairs(children) do
            local placement = type(child) == "table" and child.panel or nil
            local column = type(placement) == "table" and ResolvePanelColumn(node, placement.column) or nil
            table.insert(entries, {
                child = child,
                index = index,
                line = type(placement) == "table" and placement.line or 1,
                start = type(column) == "table" and column.start or nil,
                width = type(column) == "table" and column.width or nil,
                align = type(column) == "table" and column.align or nil,
                slots = type(placement) == "table" and placement.slots or nil,
            })
        end

        table.sort(entries, function(a, b)
            if a.line ~= b.line then
                return a.line < b.line
            end
            if type(a.start) == "number" and type(b.start) == "number" and a.start ~= b.start then
                return a.start < b.start
            end
            return a.index < b.index
        end)

        local changed = false
        local currentLine = nil

        for _, entry in ipairs(entries) do
            if currentLine ~= entry.line then
                if currentLine ~= nil then
                    imgui.NewLine()
                end
                currentLine = entry.line
            else
                imgui.SameLine()
            end

            if type(entry.start) == "number" then
                imgui.SetCursorPosX(rowStart + entry.start)
            end

            local runtimeGeometry = nil
            if type(entry.slots) == "table" and #entry.slots > 0 then
                runtimeGeometry = { slots = {} }
                for _, slotName in ipairs(entry.slots) do
                    table.insert(runtimeGeometry.slots, {
                        name = slotName,
                        start = 0,
                        width = entry.width,
                        align = entry.align,
                    })
                end
            end

            if drawChild(entry.child, runtimeGeometry) then
                changed = true
            end
        end

        return true, changed
    end,
}

local function DrawLayoutNode(imgui, node, drawChild, layoutTypes)
    local layoutType = layoutTypes[node.type]
    if not layoutType then
        return false, false
    end
    -- Layout render contract:
    --   open = render(imgui, node, drawChild)
    --   or, when layoutType.handlesChildren == true:
    --   open, changed = render(imgui, node, drawChild)
    -- Layouts with handlesChildren = true fully own child rendering and must
    -- report any child-driven change via the second return value.
    local open, layoutChanged = layoutType.render(imgui, node, drawChild)
    if layoutType.handlesChildren == true then
        return true, layoutChanged == true
    end
    local changed = false
    if open and type(node.children) == "table" then
        if node.type == "group" then imgui.Indent() end
        for _, child in ipairs(node.children) do
            if drawChild(child) then changed = true end
        end
        if node.type == "group" then imgui.Unindent() end
    end
    return true, changed
end

registry.DrawLayoutNode = DrawLayoutNode
