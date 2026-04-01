local internal = AdamantModpackLib_Internal
local shared = internal.shared
local FieldTypes = shared.FieldTypes
local libWarn = shared.libWarn
local PrepareSchemaFieldRuntimeMetadata = shared.PrepareSchemaFieldRuntimeMetadata
local IsSchemaConfigField = shared.IsSchemaConfigField
local ChoiceDisplay = shared.ChoiceDisplay

--- Render a schema field widget. Returns (newValue, changed).
--- @param imgui table
--- @param field table
--- @param value any
--- @param width number|nil
--- @return any, boolean
function public.drawField(imgui, field, value, width)
    local ft = FieldTypes[field.type]
    if ft then
        if not field._imguiId then
            field._imguiId = "##" .. tostring(field._schemaKey or field.configKey)
        end
        return ft.draw(imgui, field, value, width)
    end
    libWarn("drawField: unknown type '%s'", field.type)
    return value, false
end

--- Return whether a field should be rendered given the current flat option values.
--- @param field table
--- @param values table
--- @return boolean
function public.isFieldVisible(field, values)
    if not field.visibleIf then
        return true
    end
    return values and values[field.visibleIf] == true or false
end

--- Validate a schema at declaration time. Warns via libWarn.
--- @param schema table
--- @param label string
function public.validateSchema(schema, label)
    if type(schema) ~= "table" then
        libWarn("%s: schema is not a table", label)
        return
    end

    local knownKeys = {}
    for _, field in ipairs(schema) do
        if field.configKey ~= nil and type(field.configKey) == "string" then
            knownKeys[field.configKey] = true
        end
    end

    local seenKeys = {}
    local configFields = {}
    for i, field in ipairs(schema) do
        local prefix = label .. " field #" .. i
        local ft = nil
        if field.type ~= "separator" and not field.configKey then
            libWarn("%s: missing configKey", prefix)
        end
        if not field.type then
            libWarn("%s: missing type", prefix)
        else
            ft = FieldTypes[field.type]
            if not ft then
                libWarn("%s: unknown type '%s'", prefix, field.type)
            elseif ft.validate then
                field._imguiId = "##" .. tostring(field.configKey)
                ft.validate(field, prefix)
            end
            if field.visibleIf ~= nil and type(field.visibleIf) ~= "string" then
                libWarn("%s: visibleIf must be a flat string configKey", prefix)
            elseif field.visibleIf ~= nil and not knownKeys[field.visibleIf] then
                libWarn("%s: visibleIf '%s' does not match any configKey in this schema; hosted rendering treats it as module-local",
                    prefix, tostring(field.visibleIf))
            end
            if field.indent ~= nil and type(field.indent) ~= "boolean" then
                libWarn("%s: indent must be boolean", prefix)
            end
        end

        if field.configKey and ft then
            PrepareSchemaFieldRuntimeMetadata(field)
            if IsSchemaConfigField(field) then
                if seenKeys[field._schemaKey] then
                    libWarn("%s: duplicate configKey '%s'", prefix, field._schemaKey)
                else
                    seenKeys[field._schemaKey] = true
                    table.insert(configFields, field)
                end
            end
        end
    end
    schema._configFields = configFields
end

local function NormalizeInteger(field, value)
    local num = tonumber(value)
    if num == nil then
        num = tonumber(field.default) or 0
    end
    num = math.floor(num)
    if field.min ~= nil and num < field.min then
        num = field.min
    end
    if field.max ~= nil and num > field.max then
        num = field.max
    end
    return num
end
shared.NormalizeInteger = NormalizeInteger

FieldTypes.checkbox = {
    validate = function(field, prefix)
        if field.default ~= nil and type(field.default) ~= "boolean" then
            libWarn("%s: checkbox default must be boolean, got %s", prefix, type(field.default))
        end
    end,
    toHash    = function(_, value) return value and "1" or "0" end,
    fromHash  = function(_, str) return str == "1" end,
    toStaging = function(val) return val == true end,
    draw = function(imgui, field, value)
        if value == nil then value = field.default end
        local label = tostring(field.label or field.configKey)
        local newVal, changed = imgui.Checkbox(label .. (field._imguiId or ""), value or false)
        if imgui.IsItemHovered() and (field.tooltip or "") ~= "" then
            imgui.SetTooltip(field.tooltip)
        end
        return newVal, changed
    end,
}

FieldTypes.dropdown = {
    validate = function(field, prefix)
        if not field.values then
            libWarn("%s: dropdown missing values list", prefix)
        elseif type(field.values) ~= "table" or #field.values == 0 then
            libWarn("%s: dropdown values must be a non-empty list", prefix)
        else
            for _, v in ipairs(field.values) do
                if type(v) == "string" and string.find(v, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, v)
                end
            end
        end
        if field.displayValues ~= nil and type(field.displayValues) ~= "table" then
            libWarn("%s: dropdown displayValues must be a table", prefix)
        end
    end,
    toHash = function(_, value) return tostring(value) end,
    fromHash = function(field, str)
        for _, v in ipairs(field.values or {}) do
            if v == str then return str end
        end
        return field.default
    end,
    toStaging = function(val) return val end,
    draw = function(imgui, field, value, width)
        local current = value or field.default or ""
        local currentIdx = 1
        for i, v in ipairs(field.values) do
            if v == current then currentIdx = i; break end
        end
        local previewValue = field.values[currentIdx] or ""
        local preview = ChoiceDisplay(field, previewValue)
        imgui.Text(field.label or field.configKey)
        if imgui.IsItemHovered() and (field.tooltip or "") ~= "" then
            imgui.SetTooltip(field.tooltip)
        end
        imgui.SameLine()
        if width then imgui.PushItemWidth(width) end
        local changed = false
        local newVal = current
        if imgui.BeginCombo(field._imguiId, preview) then
            for i, v in ipairs(field.values) do
                if imgui.Selectable(ChoiceDisplay(field, v), i == currentIdx) then
                    if i ~= currentIdx then
                        newVal = v
                        changed = true
                    end
                end
            end
            imgui.EndCombo()
        end
        if width then imgui.PopItemWidth() end
        return newVal, changed
    end,
}

FieldTypes.radio = {
    validate = function(field, prefix)
        if not field.values then
            libWarn("%s: radio missing values list", prefix)
        elseif type(field.values) ~= "table" or #field.values == 0 then
            libWarn("%s: radio values must be a non-empty list", prefix)
        else
            for _, v in ipairs(field.values) do
                if type(v) == "string" and string.find(v, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, v)
                end
            end
        end
        if field.displayValues ~= nil and type(field.displayValues) ~= "table" then
            libWarn("%s: radio displayValues must be a table", prefix)
        end
    end,
    toHash = function(_, value) return tostring(value) end,
    fromHash = function(field, str)
        for _, v in ipairs(field.values or {}) do
            if v == str then return str end
        end
        return field.default
    end,
    toStaging = function(val) return val end,
    draw = function(imgui, field, value)
        local current = value or field.default or ""
        imgui.Text(field.label or field.configKey)
        if imgui.IsItemHovered() and (field.tooltip or "") ~= "" then
            imgui.SetTooltip(field.tooltip)
        end
        local newVal = current
        local changed = false
        for _, v in ipairs(field.values) do
            if imgui.RadioButton(ChoiceDisplay(field, v), current == v) then
                if v ~= current then
                    newVal = v
                    changed = true
                end
            end
            imgui.SameLine()
        end
        imgui.NewLine()
        return newVal, changed
    end,
}

FieldTypes.int32 = {
    validate = function(field, prefix)
        if field.default ~= nil and type(field.default) ~= "number" then
            libWarn("%s: int32 default must be number, got %s", prefix, type(field.default))
        end
    end,
    toHash = function(field, value)
        return tostring(NormalizeInteger(field, value))
    end,
    fromHash = function(field, str)
        return NormalizeInteger(field, tonumber(str))
    end,
    toStaging = function(val, field)
        return NormalizeInteger(field or {}, val)
    end,
    draw = function(_, _, value)
        return value, false
    end,
}

FieldTypes.stepper = {
    validate = function(field, prefix)
        if type(field.default) ~= "number" then
            libWarn("%s: stepper default must be number, got %s", prefix, type(field.default))
        end
        if type(field.min) ~= "number" then
            libWarn("%s: stepper min must be number, got %s", prefix, type(field.min))
        end
        if type(field.max) ~= "number" then
            libWarn("%s: stepper max must be number, got %s", prefix, type(field.max))
        end
        if type(field.min) == "number" and type(field.max) == "number" and field.min > field.max then
            libWarn("%s: stepper min cannot exceed max", prefix)
        end
        if field.step ~= nil and (type(field.step) ~= "number" or field.step <= 0) then
            libWarn("%s: stepper step must be a positive number", prefix)
        end
        field._step = math.floor(tonumber(field.step) or 1)
    end,
    toHash = function(field, value)
        return tostring(NormalizeInteger(field, value))
    end,
    fromHash = function(field, str)
        return NormalizeInteger(field, tonumber(str))
    end,
    toStaging = function(val, field)
        return NormalizeInteger(field or {}, val)
    end,
    draw = function(imgui, field, value)
        local current = NormalizeInteger(field, value)
        local step = field._step or math.floor(tonumber(field.step) or 1)
        local changed = false
        local newVal = current

        imgui.Text(field.label or field.configKey)
        if imgui.IsItemHovered() and (field.tooltip or "") ~= "" then
            imgui.SetTooltip(field.tooltip)
        end
        imgui.SameLine()
        if imgui.Button("-") and current > field.min then
            newVal = NormalizeInteger(field, current - step)
            changed = newVal ~= current
        end
        imgui.SameLine()
        if field._lastStepperVal ~= newVal then
            field._lastStepperStr = tostring(newVal)
            field._lastStepperVal = newVal
        end
        imgui.Text(field._lastStepperStr)
        imgui.SameLine()
        if imgui.Button("+") and current < field.max then
            newVal = NormalizeInteger(field, current + step)
            changed = newVal ~= current
        end
        return newVal, changed
    end,
}

FieldTypes.separator = {
    validate = function(field, prefix)
        if field.label ~= nil and type(field.label) ~= "string" then
            libWarn("%s: separator label must be string", prefix)
        end
    end,
    toHash = function()
        return ""
    end,
    fromHash = function()
        return nil
    end,
    toStaging = function()
        return nil
    end,
    draw = function(imgui, field)
        if field.label and field.label ~= "" then
            imgui.Separator()
            imgui.Text(field.label)
            imgui.Separator()
        else
            imgui.Separator()
        end
        return nil, false
    end,
}

public.FieldTypes = FieldTypes
