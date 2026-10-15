-- Internal hotkey picker: modifier dropdown + key dropdown + short status on the same row. Lib draws it in each
-- module's Hotkeys & Advanced tab and on the Hotkeys overview; it is not part of the author draw surface.
--
-- The draw path allocates nothing per frame: dropdown labels are constants, combo ids live on the
-- ref, binding parses are memoized, and status text is cached on the status table.

local deps = ...

local bindings = deps.bindings
local hotkeys = deps.hotkeys
local statusColors = deps.statusColors

local widget = {}

local COMBO_FLAG_NONE = 0
local EMPTY_OPTS = {}
local DEFAULT_MODIFIER_WIDTH = 110
local DEFAULT_KEY_WIDTH = 80
local NONE_LABEL = "None"
local INVALID_LABEL = "Invalid"

local STATUS_COLORS = {
    active = statusColors.success,
    conflict = statusColors.attention,
    reserved = statusColors.attention,
    invalid = statusColors.error,
    unbound = statusColors.muted,
    disabled = statusColors.muted,
}

local MODIFIER_LABEL_BY_PREFIX = {
    ["Ctrl+Shift+Alt+"] = "Ctrl+Shift+Alt",
}
for _, choice in ipairs(bindings.MODIFIER_CHOICES) do
    MODIFIER_LABEL_BY_PREFIX[choice.prefix] = choice.label
end

local function showTooltip(imgui, tooltip)
    if tooltip ~= nil and tooltip ~= "" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
end

local function write(ref, binding)
    ref.field:write(binding)
end

---@param imgui table
---@param ref AdamantModpackLib.HotkeyRef
---@param opts? AdamantModpackLib.HotkeyWidgetOpts
---@return boolean changed
function widget.draw(imgui, ref, opts)
    opts = opts or EMPTY_OPTS
    local tooltip = opts.tooltip or ref.tooltip

    local current = ref.field:read()
    local parsed = bindings.parse(current)
    local prefix
    local keyIndex = nil
    if parsed ~= nil then
        prefix = parsed.prefix
        keyIndex = parsed.keyIndex
        ref.pendingPrefix = nil
    else
        -- Unbound (or invalid) keeps the modifier picked before a key, so the order of picks
        -- does not matter.
        prefix = ref.pendingPrefix or ""
    end
    local invalid = parsed == nil and current ~= bindings.UNBOUND

    local label = opts.label
    if label == nil then
        label = ref.label
    end
    if label ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(label)
        showTooltip(imgui, tooltip)
        imgui.SameLine()
    end

    local changed = false

    imgui.PushItemWidth(opts.modifierWidth or DEFAULT_MODIFIER_WIDTH)
    if imgui.BeginCombo(ref.modifierComboId, MODIFIER_LABEL_BY_PREFIX[prefix], COMBO_FLAG_NONE) then
        for _, choice in ipairs(bindings.MODIFIER_CHOICES) do
            if imgui.Selectable(choice.label, choice.prefix == prefix) and choice.prefix ~= prefix then
                if keyIndex ~= nil then
                    write(ref, bindings.format(choice.prefix, bindings.KEYS[keyIndex]))
                    changed = true
                else
                    ref.pendingPrefix = choice.prefix
                end
                prefix = choice.prefix
            end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
    showTooltip(imgui, tooltip)

    imgui.SameLine()
    local keyPreview = keyIndex ~= nil and bindings.KEYS[keyIndex] or (invalid and INVALID_LABEL or NONE_LABEL)
    imgui.PushItemWidth(opts.keyWidth or DEFAULT_KEY_WIDTH)
    if imgui.BeginCombo(ref.keyComboId, keyPreview, COMBO_FLAG_NONE) then
        if imgui.Selectable(NONE_LABEL, keyIndex == nil and not invalid) and (keyIndex ~= nil or invalid) then
            ref.pendingPrefix = prefix
            write(ref, bindings.UNBOUND)
            changed = true
            keyIndex = nil
        end
        for index, key in ipairs(bindings.KEYS) do
            if imgui.Selectable(key, index == keyIndex) and index ~= keyIndex then
                write(ref, bindings.format(prefix, key))
                changed = true
                keyIndex = index
            end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
    showTooltip(imgui, tooltip)

    if opts.showStatus ~= false then
        local status = hotkeys.refStatus(ref)
        if status ~= nil then
            local color = STATUS_COLORS[status.state]
            imgui.SameLine()
            imgui.AlignTextToFramePadding()
            imgui.TextColored(color[1], color[2], color[3], color[4], status.text)
            showTooltip(imgui, status.detail)
        end
    end

    return changed
end

return widget
