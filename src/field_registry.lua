local internal = AdamantModpackLib_Internal
local shared = internal.shared
local StorageTypes = shared.StorageTypes
local WidgetTypes = shared.WidgetTypes
local LayoutTypes = shared.LayoutTypes
local libWarn = shared.libWarn

local REQUIRED_STORAGE_METHODS = { "validate", "normalize", "toHash", "fromHash" }
local REQUIRED_WIDGET_METHODS  = { "validate", "draw" }
local REQUIRED_LAYOUT_METHODS  = { "validate", "render" }

local function KeyStr(key)
    if type(key) == "table" then
        return table.concat(key, ".")
    end
    return tostring(key)
end

shared.StorageKey = KeyStr

local function NormalizeInteger(node, value)
    local num = tonumber(value)
    if num == nil then
        num = tonumber(node.default) or 0
    end
    num = math.floor(num)
    if node.min ~= nil and num < node.min then num = node.min end
    if node.max ~= nil and num > node.max then num = node.max end
    return num
end

shared.NormalizeInteger = NormalizeInteger

local function NormalizeChoiceValue(node, value)
    local normalized = value ~= nil and tostring(value) or tostring(node.default or "")
    if type(node.values) == "table" then
        for _, candidate in ipairs(node.values) do
            if candidate == normalized then
                return normalized
            end
        end
    end
    return node.default or ""
end

local function ChoiceDisplay(node, value)
    if node.displayValues and node.displayValues[value] ~= nil then
        return tostring(node.displayValues[value])
    end
    return tostring(value)
end

shared.ChoiceDisplay = ChoiceDisplay

local function AssertRegistryContracts(registry, required, label)
    for typeName, item in pairs(registry) do
        if type(item) ~= "table" then
            error(("%s type '%s' must be a table"):format(label, tostring(typeName)), 0)
        end
        for _, method in ipairs(required) do
            if type(item[method]) ~= "function" then
                error(("%s type '%s' is missing required method '%s'"):format(
                    label, tostring(typeName), method), 0)
            end
        end
    end
end

local function ValidateCustomTypes(customTypes, label)
    if type(customTypes) ~= "table" then
        error((label or "module") .. ": definition.customTypes must be a table", 0)
    end
    local widgets = customTypes.widgets
    local layouts = customTypes.layouts
    if widgets ~= nil then
        if type(widgets) ~= "table" then
            error((label or "module") .. ": customTypes.widgets must be a table", 0)
        end
        for typeName, item in pairs(widgets) do
            if WidgetTypes[typeName] then
                error(("%s: customTypes.widgets '%s' collides with built-in widget type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            if LayoutTypes[typeName] then
                error(("%s: customTypes.widgets '%s' collides with built-in layout type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            AssertRegistryContracts({ [typeName] = item }, REQUIRED_WIDGET_METHODS, "Widget")
            if type(item) == "table" and type(item.binds) ~= "table" then
                error(("%s: customTypes.widgets '%s' must declare a binds table"):format(
                    label or "module", tostring(typeName)), 0)
            end
        end
    end
    if layouts ~= nil then
        if type(layouts) ~= "table" then
            error((label or "module") .. ": customTypes.layouts must be a table", 0)
        end
        for typeName, item in pairs(layouts) do
            if WidgetTypes[typeName] then
                error(("%s: customTypes.layouts '%s' collides with built-in widget type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            if LayoutTypes[typeName] then
                error(("%s: customTypes.layouts '%s' collides with built-in layout type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            AssertRegistryContracts({ [typeName] = item }, REQUIRED_LAYOUT_METHODS, "Layout")
        end
    end
end

local function MergeCustomTypes(customTypes)
    if not customTypes then
        return WidgetTypes, LayoutTypes
    end
    local mergedWidgets = {}
    for k, v in pairs(WidgetTypes) do mergedWidgets[k] = v end
    if type(customTypes.widgets) == "table" then
        for k, v in pairs(customTypes.widgets) do mergedWidgets[k] = v end
    end
    local mergedLayouts = {}
    for k, v in pairs(LayoutTypes) do mergedLayouts[k] = v end
    if type(customTypes.layouts) == "table" then
        for k, v in pairs(customTypes.layouts) do mergedLayouts[k] = v end
    end
    return mergedWidgets, mergedLayouts
end

function public.validateRegistries()
    AssertRegistryContracts(StorageTypes, REQUIRED_STORAGE_METHODS, "Storage")
    AssertRegistryContracts(WidgetTypes, REQUIRED_WIDGET_METHODS, "Widget")
    AssertRegistryContracts(LayoutTypes, REQUIRED_LAYOUT_METHODS, "Layout")
    for typeName, widgetType in pairs(WidgetTypes) do
        if type(widgetType.binds) ~= "table" then
            error(("Widget type '%s' must declare a binds table"):format(tostring(typeName)), 0)
        end
    end
    return true
end

StorageTypes.bool = {
    valueKind = "bool",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "boolean" then
            libWarn("%s: bool default must be boolean, got %s", prefix, type(node.default))
        end
    end,
    normalize = function(_, value)
        return value == true
    end,
    toHash = function(_, value)
        return value and "1" or "0"
    end,
    fromHash = function(_, str)
        return str == "1"
    end,
    packWidth = function(_)
        return 1
    end,
}

StorageTypes.int = {
    valueKind = "int",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "number" then
            libWarn("%s: int default must be number, got %s", prefix, type(node.default))
        end
        if node.min ~= nil and type(node.min) ~= "number" then
            libWarn("%s: int min must be number, got %s", prefix, type(node.min))
        end
        if node.max ~= nil and type(node.max) ~= "number" then
            libWarn("%s: int max must be number, got %s", prefix, type(node.max))
        end
        if type(node.min) == "number" and type(node.max) == "number" and node.min > node.max then
            libWarn("%s: int min cannot exceed max", prefix)
        end
        if node.width ~= nil and (type(node.width) ~= "number" or node.width < 1) then
            libWarn("%s: int width must be a positive number", prefix)
        end
    end,
    normalize = function(node, value)
        return NormalizeInteger(node, value)
    end,
    toHash = function(node, value)
        return tostring(NormalizeInteger(node, value))
    end,
    fromHash = function(node, str)
        return NormalizeInteger(node, tonumber(str))
    end,
    packWidth = function(node)
        if type(node.width) == "number" and node.width >= 1 then
            return math.floor(node.width)
        end
        if type(node.min) == "number" and type(node.max) == "number" then
            local range = node.max - node.min
            if range <= 0 then return 1 end
            return math.ceil(math.log(range + 1) / math.log(2))
        end
        return nil
    end,
}

StorageTypes.string = {
    valueKind = "string",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "string" then
            libWarn("%s: string default must be string, got %s", prefix, type(node.default))
        end
        if node.maxLen ~= nil and (type(node.maxLen) ~= "number" or node.maxLen < 1) then
            libWarn("%s: string maxLen must be a positive number", prefix)
        end
        node._maxLen = math.floor(tonumber(node.maxLen) or 256)
        if node._maxLen < 1 then node._maxLen = 256 end
    end,
    normalize = function(node, value)
        return value ~= nil and tostring(value) or (node.default or "")
    end,
    toHash = function(_, value)
        return tostring(value or "")
    end,
    fromHash = function(node, str)
        return str ~= nil and tostring(str) or (node.default or "")
    end,
}

StorageTypes.packedInt = {
    valueKind = "int",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "number" then
            libWarn("%s: packedInt default must be number, got %s", prefix, type(node.default))
        end
        if type(node.bits) ~= "table" or #node.bits == 0 then
            libWarn("%s: packedInt bits must be a non-empty list", prefix)
            return
        end

        local seenAliases = {}
        local occupiedBits = {}
        for index, bitNode in ipairs(node.bits) do
            local bitPrefix = prefix .. " bits[" .. index .. "]"
            if type(bitNode.alias) ~= "string" or bitNode.alias == "" then
                libWarn("%s: packed bit alias must be a non-empty string", bitPrefix)
            elseif seenAliases[bitNode.alias] then
                libWarn("%s: duplicate packed bit alias '%s'", bitPrefix, bitNode.alias)
            else
                seenAliases[bitNode.alias] = true
            end
            if type(bitNode.offset) ~= "number" or bitNode.offset < 0 then
                libWarn("%s: packed bit offset must be a non-negative number", bitPrefix)
            end
            if type(bitNode.width) ~= "number" or bitNode.width < 1 then
                libWarn("%s: packed bit width must be a positive number", bitPrefix)
            end

            if type(bitNode.offset) == "number" and type(bitNode.width) == "number" then
                local offset = math.floor(bitNode.offset)
                local width = math.floor(bitNode.width)
                if offset + width > 32 then
                    libWarn("%s: packed bit offset + width must stay within 32 bits", bitPrefix)
                end
                for bit = offset, offset + width - 1 do
                    if occupiedBits[bit] then
                        libWarn("%s: packed bit overlaps bit %d", bitPrefix, bit)
                    else
                        occupiedBits[bit] = true
                    end
                end
                bitNode.offset = offset
                bitNode.width = width
            end

            local valueType = bitNode.type or (bitNode.width == 1 and "bool" or "int")
            if valueType ~= "bool" and valueType ~= "int" then
                libWarn("%s: packed bit type must be 'bool' or 'int'", bitPrefix)
                valueType = bitNode.width == 1 and "bool" or "int"
            end
            bitNode.type = valueType
            local storageType = StorageTypes[valueType]
            if storageType then
                storageType.validate(bitNode, bitPrefix)
            end
        end
    end,
    normalize = function(node, value)
        return NormalizeInteger(node, value)
    end,
    toHash = function(node, value)
        return tostring(NormalizeInteger(node, value))
    end,
    fromHash = function(node, str)
        return NormalizeInteger(node, tonumber(str))
    end,
}

-- Private render helpers used for internal widget composition.
-- These are pure render functions: take a value, return (newValue, changed).
-- Widget draw functions use these internally; drawUiNode uses the bound contract.

local function RenderStepper(imgui, node, value)
    local current = NormalizeInteger(node, value)
    local step = node._step or 1
    local fastStep = node._fastStep
    local newValue = current
    local changed = false

    local labelStart = imgui.GetCursorPosX()
    imgui.Text(node.label or "")
    if imgui.IsItemHovered() and (node.tooltip or "") ~= "" then
        imgui.SetTooltip(node.tooltip)
    end
    if node.controlOffset then
        imgui.SetCursorPosX(labelStart + node.controlOffset)
    else
        imgui.SameLine()
    end

    if imgui.Button("-") and current > node.min then
        newValue = NormalizeInteger(node, current - step)
        changed = newValue ~= current
    end
    imgui.SameLine()
    local valueStart = imgui.GetCursorPosX()
    if node._lastStepperVal ~= newValue then
        node._lastStepperStr = tostring(newValue)
        node._lastStepperVal = newValue
    end
    imgui.Text(node._lastStepperStr)
    imgui.SameLine()
    if node.valueWidth then
        imgui.SetCursorPosX(valueStart + node.valueWidth)
    end
    if imgui.Button("+") and current < node.max then
        newValue = NormalizeInteger(node, current + step)
        changed = newValue ~= current
    end
    if fastStep then
        imgui.SameLine()
        if imgui.Button("<<") and current > node.min then
            newValue = NormalizeInteger(node, current - fastStep)
            changed = newValue ~= current
        end
        imgui.SameLine()
        if imgui.Button(">>") and current < node.max then
            newValue = NormalizeInteger(node, current + fastStep)
            changed = newValue ~= current
        end
    end
    return newValue, changed
end

WidgetTypes.checkbox = {
    binds = { value = { storageType = "bool" } },
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "boolean" then
            libWarn("%s: checkbox default must be boolean, got %s", prefix, type(node.default))
        end
    end,
    draw = function(imgui, node, bound)
        local value = bound.value:get()
        if value == nil then value = node.default == true end
        local label = tostring(node.label or (node.binds and node.binds.value) or "")
        local newVal, changed = imgui.Checkbox(label .. (node._imguiId or ""), value == true)
        if imgui.IsItemHovered() and (node.tooltip or "") ~= "" then
            imgui.SetTooltip(node.tooltip)
        end
        if changed then bound.value:set(newVal) end
    end,
}

WidgetTypes.dropdown = {
    binds = { value = { storageType = "string" } },
    validate = function(node, prefix)
        if not node.values then
            libWarn("%s: dropdown missing values list", prefix)
        elseif type(node.values) ~= "table" or #node.values == 0 then
            libWarn("%s: dropdown values must be a non-empty list", prefix)
        else
            for _, value in ipairs(node.values) do
                if type(value) == "string" and string.find(value, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, value)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: dropdown displayValues must be a table", prefix)
        end
        if node.controlOffset ~= nil and (type(node.controlOffset) ~= "number" or node.controlOffset <= 0) then
            libWarn("%s: dropdown controlOffset must be a positive number", prefix)
        end
    end,
    draw = function(imgui, node, bound, width)
        local current = NormalizeChoiceValue(node, bound.value:get())
        local currentIdx = 1
        for index, candidate in ipairs(node.values or {}) do
            if candidate == current then currentIdx = index; break end
        end

        local previewValue = (node.values and node.values[currentIdx]) or ""
        local getCursorPosX = imgui.GetCursorPosX
        local labelStart = type(getCursorPosX) == "function" and getCursorPosX() or 0

        imgui.Text(node.label or (node.binds and node.binds.value) or "")
        if imgui.IsItemHovered() and (node.tooltip or "") ~= "" then
            imgui.SetTooltip(node.tooltip)
        end
        if node.controlOffset then
            if type(imgui.SetCursorPosX) == "function" then
                imgui.SetCursorPosX(labelStart + node.controlOffset)
            else
                imgui.SameLine()
            end
        else
            imgui.SameLine()
        end

        if width then imgui.PushItemWidth(width) end
        if imgui.BeginCombo(node._imguiId, ChoiceDisplay(node, previewValue)) then
            for index, candidate in ipairs(node.values or {}) do
                if imgui.Selectable(ChoiceDisplay(node, candidate), index == currentIdx) then
                    if candidate ~= current then
                        bound.value:set(candidate)
                    end
                end
            end
            imgui.EndCombo()
        end
        if width then imgui.PopItemWidth() end
    end,
}

WidgetTypes.radio = {
    binds = { value = { storageType = "string" } },
    validate = function(node, prefix)
        if not node.values then
            libWarn("%s: radio missing values list", prefix)
        elseif type(node.values) ~= "table" or #node.values == 0 then
            libWarn("%s: radio values must be a non-empty list", prefix)
        else
            for _, value in ipairs(node.values) do
                if type(value) == "string" and string.find(value, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, value)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: radio displayValues must be a table", prefix)
        end
    end,
    draw = function(imgui, node, bound)
        local current = NormalizeChoiceValue(node, bound.value:get())
        imgui.Text(node.label or (node.binds and node.binds.value) or "")
        if imgui.IsItemHovered() and (node.tooltip or "") ~= "" then
            imgui.SetTooltip(node.tooltip)
        end
        for index, candidate in ipairs(node.values or {}) do
            if index > 1 then imgui.SameLine() end
            if imgui.RadioButton(ChoiceDisplay(node, candidate), current == candidate) then
                if candidate ~= current then
                    bound.value:set(candidate)
                end
            end
        end
        imgui.NewLine()
    end,
}

local function ValidateStepper(node, prefix)
    StorageTypes.int.validate(node, prefix)
    if node.step ~= nil and (type(node.step) ~= "number" or node.step <= 0) then
        libWarn("%s: stepper step must be a positive number", prefix)
    end
    if node.fastStep ~= nil and (type(node.fastStep) ~= "number" or node.fastStep <= 0) then
        libWarn("%s: stepper fastStep must be a positive number", prefix)
    end
    if node.controlOffset ~= nil and (type(node.controlOffset) ~= "number" or node.controlOffset <= 0) then
        libWarn("%s: stepper controlOffset must be a positive number", prefix)
    end
    if node.valueWidth ~= nil and (type(node.valueWidth) ~= "number" or node.valueWidth <= 0) then
        libWarn("%s: stepper valueWidth must be a positive number", prefix)
    end
    node._step = math.floor(tonumber(node.step) or 1)
    node._fastStep = node.fastStep and math.floor(node.fastStep) or nil
end

WidgetTypes.stepper = {
    binds = { value = { storageType = "int" } },
    validate = ValidateStepper,
    draw = function(imgui, node, bound)
        local newValue, changed = RenderStepper(imgui, node, bound.value:get())
        if changed then bound.value:set(newValue) end
    end,
}

WidgetTypes.steppedRange = {
    binds = {
        min = { storageType = "int" },
        max = { storageType = "int" },
    },
    validate = function(node, prefix)
        if node.controlOffset ~= nil and (type(node.controlOffset) ~= "number" or node.controlOffset <= 0) then
            libWarn("%s: steppedRange controlOffset must be a positive number", prefix)
        end
        if node.separatorWidth ~= nil and (type(node.separatorWidth) ~= "number" or node.separatorWidth <= 0) then
            libWarn("%s: steppedRange separatorWidth must be a positive number", prefix)
        end
        local minStepper = {
            label = node.label,
            default = node.default,
            min = node.min, max = node.max,
            step = node.step, fastStep = node.fastStep,
            controlOffset = node.controlOffset, valueWidth = node.valueWidth,
        }
        local maxStepper = {
            default = node.defaultMax or node.default,
            min = node.min, max = node.max,
            step = node.step, fastStep = node.fastStep,
            valueWidth = node.valueWidth,
        }
        ValidateStepper(minStepper, prefix .. " min")
        ValidateStepper(maxStepper, prefix .. " max")
        node._minStepper = minStepper
        node._maxStepper = maxStepper
    end,
    draw = function(imgui, node, bound)
        local minStepper = node._minStepper
        local maxStepper = node._maxStepper
        if not minStepper or not maxStepper then
            libWarn("steppedRange '%s' not prepared", tostring(node.binds and node.binds.min or node.type))
            return
        end

        local minValue = bound.min:get()
        local maxValue = bound.max:get()
        minStepper.max = maxValue
        maxStepper.min = minValue

        if node.label and node.label ~= "" then
            local labelStart = imgui.GetCursorPosX()
            imgui.Text(node.label)
            if node.controlOffset then
                imgui.SetCursorPosX(labelStart + node.controlOffset)
            else
                imgui.SameLine()
            end
        end

        imgui.PushID((node._imguiId or "range") .. "_min")
        local newMin, minChanged = RenderStepper(imgui, minStepper, minValue)
        imgui.PopID()

        -- update live constraint before rendering max
        maxStepper.min = newMin

        if node.separatorWidth then
            local TO_HALF_WIDTH = 7
            local afterMin = imgui.GetCursorPosX()
            imgui.SetCursorPosX(afterMin + node.separatorWidth / 2 - TO_HALF_WIDTH)
            imgui.Text("to")
            imgui.SetCursorPosX(afterMin + node.separatorWidth)
        else
            imgui.SameLine()
            imgui.Text("to")
            imgui.SameLine()
        end

        imgui.PushID((node._imguiId or "range") .. "_max")
        local newMax, maxChanged = RenderStepper(imgui, maxStepper, maxValue)
        imgui.PopID()

        if minChanged then bound.min:set(newMin) end
        if maxChanged then bound.max:set(newMax) end
    end,
}

WidgetTypes.packedCheckboxList = {
    binds = { value = { storageType = "int" } },
    validate = function(_, _)
        -- child list is runtime-resolved from the packedInt root at draw time
    end,
    draw = function(imgui, node, bound)
        local children = bound.value and bound.value.children
        if not children or #children == 0 then
            libWarn("packedCheckboxList: no packed children for alias '%s'; bind to a packedInt root",
                tostring(node.binds and node.binds.value or "?"))
            return
        end
        for _, child in ipairs(children) do
            local val = child.get()
            if val == nil then val = false end
            imgui.PushID(child.alias)
            local newVal, changed = imgui.Checkbox(child.label, val == true)
            if changed then child.set(newVal) end
            imgui.PopID()
        end
    end,
}

LayoutTypes.separator = {
    validate = function(node, prefix)
        if node.label ~= nil and type(node.label) ~= "string" then
            libWarn("%s: separator label must be string", prefix)
        end
    end,
    render = function(imgui, node)
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
    render = function(imgui, node)
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

local function PrepareRootNodeMetadata(node)
    node._storageKey = KeyStr(node.configKey)
    if not node.alias then
        node.alias = node._storageKey
    end
end

local function ValidateChildAlias(bitNode, root, storage, seenAliases, seenRootKeys, prefix)
    if type(bitNode.alias) ~= "string" or bitNode.alias == "" then
        return
    end

    if seenAliases[bitNode.alias] then
        libWarn("%s: duplicate alias '%s'", prefix, bitNode.alias)
        return
    end
    local ownerKey = seenRootKeys[bitNode.alias]
    if ownerKey and ownerKey ~= root._storageKey then
        libWarn("%s: alias '%s' conflicts with root configKey '%s'", prefix, bitNode.alias, ownerKey)
        return
    end

    local storageType = StorageTypes[bitNode.type]
    local child = {
        alias = bitNode.alias,
        label = bitNode.label or bitNode.alias,
        type = bitNode.type,
        default = bitNode.default,
        min = bitNode.min,
        max = bitNode.max,
        offset = bitNode.offset,
        width = bitNode.width,
        parent = root,
        _isBitAlias = true,
        _storageKey = root._storageKey .. "." .. bitNode.alias,
        _valueKind = storageType and storageType.valueKind or bitNode.type,
    }
    if child.type == "bool" and child.default == nil then
        child.default = false
    end
    if child.type == "int" and child.default == nil then
        child.default = 0
    end

    seenAliases[child.alias] = true
    storage._aliasNodes[child.alias] = child
    root._bitAliases[#root._bitAliases + 1] = child
end

function public.validateStorage(storage, label)
    if type(storage) ~= "table" then
        libWarn("%s: storage is not a table", label)
        return
    end

    storage._rootNodes = {}
    storage._aliasNodes = {}
    storage._rootByKey = {}

    local seenAliases = {}
    local seenRootKeys = {}

    for index, node in ipairs(storage) do
        local prefix = label .. " storage #" .. index
        if type(node) ~= "table" then
            libWarn("%s: storage entry is not a table", prefix)
        elseif not node.type then
            libWarn("%s: missing type", prefix)
        else
            local storageType = StorageTypes[node.type]
            if not storageType then
                libWarn("%s: unknown storage type '%s'", prefix, tostring(node.type))
            elseif node.type == "packedInt" and node.configKey == nil then
                libWarn("%s: packedInt is missing configKey", prefix)
            elseif node.configKey == nil then
                libWarn("%s: missing configKey", prefix)
            else
                storageType.validate(node, prefix)
                PrepareRootNodeMetadata(node)
                node._isRoot = true
                node._valueKind = storageType.valueKind
                node._bitAliases = {}

                if seenRootKeys[node._storageKey] then
                    libWarn("%s: duplicate configKey '%s'", prefix, node._storageKey)
                else
                    seenRootKeys[node._storageKey] = node._storageKey
                    storage._rootByKey[node._storageKey] = node
                end

                if type(node.alias) ~= "string" or node.alias == "" then
                    libWarn("%s: missing alias", prefix)
                elseif seenAliases[node.alias] then
                    libWarn("%s: duplicate alias '%s'", prefix, node.alias)
                else
                    seenAliases[node.alias] = true
                    storage._aliasNodes[node.alias] = node
                end

                if node.type == "packedInt" then
                    for bitIndex, bitNode in ipairs(node.bits or {}) do
                        ValidateChildAlias(
                            bitNode,
                            node,
                            storage,
                            seenAliases,
                            seenRootKeys,
                            prefix .. " bits[" .. bitIndex .. "]"
                        )
                    end

                    if node.default == nil then
                        node.default = 0
                        for _, child in ipairs(node._bitAliases) do
                            local encoded = child.type == "bool"
                                and (child.default == true and 1 or 0)
                                or child.default
                            node.default = public.writeBitsValue(node.default, child.offset, child.width, encoded)
                        end
                    else
                        node.default = NormalizeInteger(node, node.default)
                        for _, child in ipairs(node._bitAliases) do
                            if child.default == nil then
                                child.default = public.readBitsValue(node.default, child.offset, child.width)
                            else
                                local expected = public.readBitsValue(node.default, child.offset, child.width)
                                local normalized = StorageTypes[child.type].normalize(child, child.default)
                                if expected ~= normalized then
                                    libWarn("%s: packed child default '%s' does not match packedInt default",
                                        prefix, child.alias)
                                end
                            end
                        end
                    end
                end

                table.insert(storage._rootNodes, node)
            end
        end
    end
end

function public.getStorageRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_rootNodes") or {}
end

function public.getPackWidth(node)
    if type(node) ~= "table" then return nil end
    local storageType = StorageTypes[node.type]
    if storageType and storageType.packWidth then
        return storageType.packWidth(node)
    end
    return nil
end

function public.getStorageAliases(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_aliasNodes") or {}
end

local function EnsurePreparedStorage(storage, label)
    if type(storage) ~= "table" then
        return {}
    end
    if rawget(storage, "_aliasNodes") ~= nil and rawget(storage, "_rootNodes") ~= nil then
        return storage._aliasNodes
    end
    public.validateStorage(storage, label or "storage")
    return public.getStorageAliases(storage)
end

local function AssertUiBind(prefix, node, storageNodes, bindName, expectedKind)
    local alias = node.binds and node.binds[bindName]
    if type(alias) ~= "string" or alias == "" then
        libWarn("%s: missing binds.%s", prefix, bindName)
        return
    end
    local storageNode = storageNodes and storageNodes[alias] or nil
    if not storageNode then
        libWarn("%s: binds.%s unknown alias '%s'", prefix, bindName, tostring(alias))
        return
    end
    if expectedKind ~= nil and storageNode._valueKind ~= expectedKind then
        libWarn("%s: bound alias '%s' is %s, expected %s (binds.%s)",
            prefix, tostring(alias), tostring(storageNode._valueKind), tostring(expectedKind), bindName)
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
        widgetType.validate(node, prefix)
        -- Generic: validate every bind declared by the widget type
        local idParts = {}
        for bindName, bindSpec in pairs(widgetType.binds) do
            AssertUiBind(prefix, node, storageNodes, bindName, bindSpec.storageType)
            table.insert(idParts, tostring(node.binds and node.binds[bindName] or bindName))
        end
        table.sort(idParts)
        node._imguiId = "##" .. table.concat(idParts, "__")
    else
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

function public.prepareUiNodes(nodes, label, storage, customTypes)
    local prefix = label or "prepareUiNodes"
    local preparedStorage = EnsurePreparedStorage(storage, prefix .. " storage")
    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)
    local registry = {}
    for _, node in ipairs(nodes) do
        ValidateUiNode(node, prefix, preparedStorage, widgetTypes, layoutTypes)
        for _, alias in pairs(node.binds or {}) do
            registry[alias] = node
        end
    end
    return registry
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

local function DrawLayoutNode(imgui, node, drawChild, layoutTypes)
    local layoutType = layoutTypes[node.type]
    if not layoutType then
        return false, false
    end
    local open = layoutType.render(imgui, node)
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

function public.drawUiNode(imgui, node, uiState, width, customTypes)
    if not public.isUiNodeVisible(node, uiState and uiState.view) then
        return false
    end

    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)

    local function drawChild(child)
        return public.drawUiNode(imgui, child, uiState, width, customTypes)
    end

    local wasLayout, layoutChanged = DrawLayoutNode(imgui, node, drawChild, layoutTypes)
    if wasLayout then return layoutChanged end

    local widgetType = widgetTypes[node.type]
    if not widgetType then
        libWarn("drawUiNode: unknown node type '%s'", tostring(node.type))
        return false
    end

    imgui.PushID(node._imguiId or tostring(node.type))
    if node.indent then imgui.Indent() end

    -- Build bound table from widget's binds declaration.
    -- packedInt root binds also expose .children = { alias, label, get, set }.
    local bound = { _changed = false }
    for bindName in pairs(widgetType.binds) do
        local alias = node.binds and node.binds[bindName]
        if alias then
            local a = alias
            local bindEntry = {
                get = function(_) return uiState.get(a) end,
                set = function(_, val) uiState.set(a, val); bound._changed = true end,
            }
            if uiState.getAliasNode then
                local aliasNode = uiState.getAliasNode(a)
                if aliasNode and aliasNode.type == "packedInt" and aliasNode._bitAliases then
                    bindEntry.children = {}
                    for _, child in ipairs(aliasNode._bitAliases) do
                        local childAlias = child.alias
                        local childLabel = child.label or childAlias
                        table.insert(bindEntry.children, {
                            alias = childAlias,
                            label = childLabel,
                            get = function() return uiState.get(childAlias) end,
                            set = function(val)
                                uiState.set(childAlias, val)
                                bound._changed = true
                            end,
                        })
                    end
                end
            end
            bound[bindName] = bindEntry
        end
    end

    widgetType.draw(imgui, node, bound, width)

    if node.indent then imgui.Unindent() end
    imgui.PopID()
    return bound._changed
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

function public.collectQuickUiNodes(nodes, out)
    out = out or {}
    if type(nodes) ~= "table" then
        return out
    end
    for _, node in ipairs(nodes) do
        if type(node) == "table" then
            if WidgetTypes[node.type] and node.quick == true then
                table.insert(out, node)
            end
            if LayoutTypes[node.type] and type(node.children) == "table" then
                public.collectQuickUiNodes(node.children, out)
            end
        end
    end
    return out
end

public.StorageTypes = StorageTypes
public.WidgetTypes = WidgetTypes
public.LayoutTypes = LayoutTypes
public.validateRegistries()
