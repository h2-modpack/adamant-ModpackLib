local helpers = ...

local DEFAULT_PACKED_SLOT_COUNT = 32

---@class CheckboxOpts
---@field label string|nil
---@field tooltip string|nil
---@field color Color|nil
---@field action DrawActionRef|nil
---@field value any

---@class PackedCheckboxListOpts
---@field filterText string|nil
---@field filterMode "all"|"checked"|"unchecked"|nil
---@field valueColors table<string, Color>|nil
---@field slotCount number|nil
---@field optionsPerLine number|nil
---@field optionGap number|nil
---@field action DrawActionRef|nil
---@field value any

---@param imgui table
---@param field StorageField
---@param opts CheckboxOpts|nil
---@return boolean
function helpers.widgets.checkbox(imgui, field, opts)
    opts = opts or {}
    local fieldAlias = field:alias()
    local fieldControlId = field:controlId()
    local label = tostring(opts.label or fieldAlias or "")
    local current = field:read() == true
    local color = helpers.NormalizeColor(opts.color)
    local nextValue, changed = helpers.DrawWithValueColor(imgui, color, function()
        return imgui.Checkbox(label .. "##" .. tostring(fieldControlId), current)
    end)
    helpers.ShowTooltip(imgui, opts.tooltip)
    if changed then
        field:write(nextValue)
        helpers.StageAction("draw.widgets.checkbox", opts, nextValue)
        return true
    end
    return false
end

---@param imgui table
---@param field StorageField
---@param opts PackedCheckboxListOpts|nil
---@return boolean
function helpers.widgets.packedCheckboxList(imgui, field, opts)
    opts = opts or {}
    local owner = helpers.GetFieldOwner(field)
    local fieldControlId = field:controlId()
    local children = helpers.ResolvePackedChildren(field)
    local lowerFilter = type(opts.filterText) == "string" and opts.filterText:lower() or ""
    local hasFilter = lowerFilter ~= ""
    local filterMode = opts.filterMode
    if filterMode ~= "checked" and filterMode ~= "unchecked" then
        filterMode = "all"
    end
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local slotCount = math.max(math.floor(tonumber(opts.slotCount) or DEFAULT_PACKED_SLOT_COUNT), 1)
    local optionsPerLine = math.floor(tonumber(opts.optionsPerLine) or 0)
    if optionsPerLine < 1 then
        optionsPerLine = 1
    end
    local optionGap = helpers.ResolveGap(imgui, opts.optionGap)
    local drawn = 0
    local changed = false

    for _, child in ipairs(children) do
        if drawn >= slotCount then
            break
        end
        local current = owner.read(child.alias) == true
        local matchesText = not hasFilter or tostring(child.label):lower():find(lowerFilter, 1, true) ~= nil
        local matchesMode = filterMode == "all"
            or (filterMode == "checked" and current)
            or (filterMode == "unchecked" and not current)
        if matchesText and matchesMode then
            drawn = drawn + 1
            local positionInLine = (drawn - 1) % optionsPerLine
            if positionInLine ~= 0 then
                helpers.SameLineWithGap(imgui, optionGap)
            end
            local color = valueColors and valueColors[child.alias] or nil
            local childControlId = tostring(fieldControlId) .. ":" .. tostring(child.alias)
            local nextValue, clicked = helpers.DrawWithValueColor(imgui, color, function()
                return imgui.Checkbox(tostring(child.label) .. "##" .. childControlId, current)
            end)
            if clicked then
                owner.write(child.alias, nextValue)
                helpers.StageAction("draw.widgets.packedCheckboxList", opts, {
                    alias = child.alias,
                    value = nextValue,
                })
                changed = true
            end
        end
    end

    return changed
end
