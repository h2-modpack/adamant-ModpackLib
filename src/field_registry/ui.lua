local internal = AdamantModpackLib_Internal
local shared = internal.shared
local WidgetTypes = shared.WidgetTypes
local LayoutTypes = shared.LayoutTypes
local libWarn = shared.libWarn
local registry = shared.fieldRegistry

local ValidateCustomTypes = registry.ValidateCustomTypes
local MergeCustomTypes = registry.MergeCustomTypes
local ValidateWidgetGeometry = registry.ValidateWidgetGeometry
local EnsurePreparedStorage = registry.EnsurePreparedStorage
local DrawLayoutNode = registry.DrawLayoutNode
local nextAnonymousImguiId = 0

local function BuildBoundEntries(node, widgetType, uiState)
    local bound = { _changed = false }
    for bindName in pairs(widgetType.binds) do
        local alias = node.binds and node.binds[bindName]
        if alias then
            local a = alias
            local aliasNode = uiState.getAliasNode and uiState.getAliasNode(a) or nil
            local bindEntry = {
                get = function(_) return uiState.get(a) end,
                set = function(_, val) uiState.set(a, val); bound._changed = true end,
                node = aliasNode,
            }
            if aliasNode and aliasNode.type == "packedInt" and aliasNode._bitAliases then
                local children = {}
                for _, child in ipairs(aliasNode._bitAliases) do
                    local childAlias = child.alias
                    local childLabel = child.label or childAlias
                    children[#children + 1] = {
                        alias = childAlias,
                        label = childLabel,
                        get = function() return uiState.get(childAlias) end,
                        set = function(val)
                            uiState.set(childAlias, val)
                            bound._changed = true
                        end,
                    }
                end
                bindEntry.children = children
            end
            bound[bindName] = bindEntry
        end
    end
    node._boundCache = bound
    node._boundCacheUiState = uiState
    node._boundCacheWidgetType = widgetType
    return bound
end

registry.BuildBoundEntries = BuildBoundEntries

local function AssertUiBind(prefix, node, storageNodes, bindName, bindSpec)
    local alias = node.binds and node.binds[bindName]
    local optional = type(bindSpec) == "table" and bindSpec.optional == true
    if type(alias) ~= "string" or alias == "" then
        if not optional then
            libWarn("%s: missing binds.%s", prefix, bindName)
        end
        return
    end
    local storageNode = storageNodes and storageNodes[alias] or nil
    if not storageNode then
        libWarn("%s: binds.%s unknown alias '%s'", prefix, bindName, tostring(alias))
        return
    end
    local expectedKind = type(bindSpec) == "table" and bindSpec.storageType or bindSpec
    if expectedKind ~= nil then
        local expectedKinds = type(expectedKind) == "table" and expectedKind or { expectedKind }

        local matchedKind = false
        for _, kind in ipairs(expectedKinds) do
            if storageNode._valueKind == kind then
                matchedKind = true
                break
            end
        end

        if not matchedKind then
            libWarn("%s: bound alias '%s' is %s, expected %s (binds.%s)",
                prefix,
                tostring(alias),
                tostring(storageNode._valueKind),
                table.concat(expectedKinds, " or "),
                bindName)
        end
    end

    local expectedRootType = type(bindSpec) == "table" and bindSpec.rootType or nil
    if expectedRootType ~= nil and storageNode.type ~= expectedRootType then
        libWarn("%s: bound alias '%s' is root type %s, expected %s (binds.%s)",
            prefix,
            tostring(alias),
            tostring(storageNode.type),
            tostring(expectedRootType),
            bindName)
    end
end

local function ValidateVisibleIf(prefix, node, storageNodes)
    if node.visibleIf == nil then
        return
    end

    if type(node.visibleIf) == "string" then
        if node.visibleIf == "" then
            libWarn("%s: visibleIf must not be empty", prefix)
            return
        end
        local visibleStorage = storageNodes and storageNodes[node.visibleIf] or nil
        if not visibleStorage then
            libWarn("%s: visibleIf alias '%s' does not exist", prefix, tostring(node.visibleIf))
        elseif visibleStorage._valueKind ~= "bool" then
            libWarn("%s: visibleIf alias '%s' must resolve to bool storage", prefix, tostring(node.visibleIf))
        end
        return
    end

    if type(node.visibleIf) ~= "table" then
        libWarn("%s: visibleIf must be a storage alias string or table", prefix)
        return
    end

    local alias = node.visibleIf.alias
    if type(alias) ~= "string" or alias == "" then
        libWarn("%s: visibleIf.alias must be a non-empty string", prefix)
        return
    end

    local visibleStorage = storageNodes and storageNodes[alias] or nil
    if not visibleStorage then
        libWarn("%s: visibleIf alias '%s' does not exist", prefix, tostring(alias))
        return
    end

    local hasValue = node.visibleIf.value ~= nil
    local hasAnyOf = node.visibleIf.anyOf ~= nil
    if hasValue and hasAnyOf then
        libWarn("%s: visibleIf cannot specify both value and anyOf", prefix)
        return
    end

    if not hasValue and not hasAnyOf then
        if visibleStorage._valueKind ~= "bool" then
            libWarn("%s: visibleIf alias '%s' must resolve to bool storage", prefix, tostring(alias))
        end
        return
    end

    if hasAnyOf then
        if type(node.visibleIf.anyOf) ~= "table" or #node.visibleIf.anyOf == 0 then
            libWarn("%s: visibleIf.anyOf must be a non-empty list", prefix)
        end
    end
end

local function DeriveQuickUiNodeId(node)
    if type(node) ~= "table" then
        return nil
    end
    if type(node.quickId) == "string" and node.quickId ~= "" then
        return node.quickId
    end
    if type(node.binds) ~= "table" then
        return nil
    end

    local parts = {}
    for bindName, alias in pairs(node.binds) do
        if type(alias) == "string" and alias ~= "" then
            table.insert(parts, tostring(bindName) .. "=" .. alias)
        end
    end
    if #parts == 0 then
        return nil
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function EnsureNodeImguiId(node, prefix, widgetType)
    if type(node) ~= "table" then
        return
    end
    if type(node._imguiId) == "string" and node._imguiId ~= "" then
        return
    end

    local idParts = {}
    local binds = type(widgetType) == "table" and type(widgetType.binds) == "table" and widgetType.binds or nil
    if binds ~= nil then
        for bindName in pairs(binds) do
            local alias = type(node.binds) == "table" and node.binds[bindName] or nil
            if type(alias) == "string" and alias ~= "" then
                table.insert(idParts, tostring(bindName) .. "=" .. alias)
            end
        end
    end
    if #idParts > 0 then
        table.sort(idParts)
        node._imguiId = "##" .. table.concat(idParts, "__")
        return
    end

    nextAnonymousImguiId = nextAnonymousImguiId + 1
    node._imguiId = string.format("##anon_%d_%s", nextAnonymousImguiId, tostring(prefix or node.type or "node"))
end

local function ValidateUiNode(node, prefix, storageNodes, widgetTypes, layoutTypes)
    widgetTypes = widgetTypes or WidgetTypes
    layoutTypes = layoutTypes or LayoutTypes
    if type(node) ~= "table" then
        libWarn("%s: ui node is not a table", prefix)
        return
    end
    if not node.type then
        libWarn("%s: missing type", prefix)
        return
    end

    local widgetType = widgetTypes[node.type]
    local layoutType = layoutTypes[node.type]
    if widgetType and layoutType then
        libWarn("%s: node type '%s' is both widget and layout", prefix, tostring(node.type))
        return
    end
    if not widgetType and not layoutType then
        libWarn("%s: unknown ui node type '%s'", prefix, tostring(node.type))
        return
    end

    if widgetType then
        node._widgetType = widgetType
        node._layoutType = nil
        widgetType.validate(node, prefix)
        ValidateWidgetGeometry(node, prefix, widgetType)
        if node.quickId ~= nil and (type(node.quickId) ~= "string" or node.quickId == "") then
            libWarn("%s: quickId must be a non-empty string", prefix)
        end
        for bindName, bindSpec in pairs(widgetType.binds) do
            AssertUiBind(prefix, node, storageNodes, bindName, bindSpec)
        end
        EnsureNodeImguiId(node, prefix, widgetType)
        node._quickId = DeriveQuickUiNodeId(node)
    else
        node._layoutType = layoutType
        node._widgetType = nil
        layoutType.validate(node, prefix)
        if node.children ~= nil then
            if type(node.children) ~= "table" then
                libWarn("%s: children must be a table", prefix)
            else
                for childIndex, child in ipairs(node.children) do
                    ValidateUiNode(child, prefix .. " child #" .. childIndex, storageNodes, widgetTypes, layoutTypes)
                end
            end
        end
    end

    ValidateVisibleIf(prefix, node, storageNodes)
end

function public.validateUi(uiNodes, label, storage, customTypes)
    if type(uiNodes) ~= "table" then
        libWarn("%s: ui is not a table", label)
        return
    end
    if customTypes ~= nil then
        ValidateCustomTypes(customTypes, label)
    end
    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)
    local storageNodes = EnsurePreparedStorage(storage, label and (label .. " storage") or "validateUi storage")
    for index, node in ipairs(uiNodes) do
        ValidateUiNode(node, label .. " ui #" .. index, storageNodes, widgetTypes, layoutTypes)
    end
end

function public.prepareUiNode(node, label, storage, customTypes)
    local prefix = label or "prepareUiNode"
    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)
    ValidateUiNode(node, prefix, EnsurePreparedStorage(storage, prefix .. " storage"), widgetTypes, layoutTypes)
end

function public.prepareWidgetNode(node, label, customTypes)
    local prefix = label or "prepareWidgetNode"
    if type(node) ~= "table" then
        libWarn("%s: widget node is not a table", prefix)
        return
    end
    if type(node.type) ~= "string" or node.type == "" then
        libWarn("%s: widget node missing type", prefix)
        return
    end
    local widgetTypes = select(1, MergeCustomTypes(customTypes))
    local widgetType = widgetTypes[node.type]
    if not widgetType then
        libWarn("%s: unknown widget type '%s'", prefix, tostring(node.type))
        return
    end
    widgetType.validate(node, prefix)
    ValidateWidgetGeometry(node, prefix, widgetType)
    EnsureNodeImguiId(node, prefix, widgetType)
end

function public.prepareUiNodes(nodes, label, storage, customTypes)
    local prefix = label or "prepareUiNodes"
    local preparedStorage = EnsurePreparedStorage(storage, prefix .. " storage")
    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)
    local registryTable = {}
    for _, node in ipairs(nodes) do
        ValidateUiNode(node, prefix, preparedStorage, widgetTypes, layoutTypes)
        for _, alias in pairs(node.binds or {}) do
            registryTable[alias] = node
        end
    end
    return registryTable
end

function public.isUiNodeVisible(node, view)
    if not node.visibleIf then
        return true
    end
    if type(node.visibleIf) == "string" then
        return view and view[node.visibleIf] == true or false
    end
    if type(node.visibleIf) ~= "table" then
        return false
    end

    local alias = node.visibleIf.alias
    if type(alias) ~= "string" or alias == "" then
        return false
    end

    local value = view and view[alias]
    if node.visibleIf.value ~= nil then
        return value == node.visibleIf.value
    end
    if node.visibleIf.anyOf ~= nil then
        if type(node.visibleIf.anyOf) ~= "table" then
            return false
        end
        for _, expected in ipairs(node.visibleIf.anyOf) do
            if value == expected then
                return true
            end
        end
        return false
    end
    return value == true
end

function public.drawUiNode(imgui, node, uiState, width, customTypes)
    if not public.isUiNodeVisible(node, uiState and uiState.view) then
        return false
    end

    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)

    local function drawChild(child)
        return public.drawUiNode(imgui, child, uiState, width, customTypes)
    end

    local wasLayout, layoutChanged = DrawLayoutNode(imgui, node, drawChild, layoutTypes, uiState)
    if wasLayout then return layoutChanged end

    local widgetType = widgetTypes[node.type]
    if not widgetType then
        libWarn("drawUiNode: unknown node type '%s'", tostring(node.type))
        return false
    end

    imgui.PushID(node._imguiId or tostring(node.type))
    if node.indent then imgui.Indent() end

    local bound = node._boundCache
    if bound == nil or node._boundCacheUiState ~= uiState or node._boundCacheWidgetType ~= widgetType then
        bound = BuildBoundEntries(node, widgetType, uiState)
    end
    bound._changed = false

    local drawChanged = false
    if type(widgetType.draw) == "function" then
        local ok, result = xpcall(function()
            return widgetType.draw(imgui, node, bound, width, uiState) == true
        end, function(err)
            return debug.traceback(err, 2)
        end)
        if not ok then
            error(result, 0)
        end
        drawChanged = result == true
    else
        libWarn("drawUiNode: widget type '%s' is missing draw", tostring(node.type))
    end

    if node.indent then imgui.Unindent() end
    imgui.PopID()
    return bound._changed or drawChanged
end

function public.drawUiTree(imgui, nodes, uiState, width, customTypes)
    if type(nodes) ~= "table" then
        return false
    end
    local changed = false
    for _, node in ipairs(nodes) do
        if public.drawUiNode(imgui, node, uiState, width, customTypes) then
            changed = true
        end
    end
    return changed
end


function public.collectQuickUiNodes(nodes, out, customTypes)
    out = out or {}
    if type(nodes) ~= "table" then
        return out
    end
    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)
    for _, node in ipairs(nodes) do
        if type(node) == "table" then
            if widgetTypes[node.type] and node.quick == true then
                node._quickId = node._quickId or DeriveQuickUiNodeId(node)
                table.insert(out, node)
            end
            if layoutTypes[node.type] and type(node.children) == "table" then
                public.collectQuickUiNodes(node.children, out, customTypes)
            end
        end
    end
    return out
end

function public.getQuickUiNodeId(node)
    return DeriveQuickUiNodeId(node)
end
