-- Lib-owned Hotkeys section of a module's Hotkeys & Advanced tab (see `core/ui/module_frame.lua`): every
-- request's row, always expanded with its status line, then "All hotkeys..." opening Lib's
-- settings window. Modules without hotkey requests draw nothing.
--
-- The draw path allocates nothing per frame: rows come from the registry's cached block and the
-- button label is built once per owner.

local deps = ...

local drawWidget = deps.drawWidget
local hotkeys = deps.hotkeys
local refForRow = deps.refForRow
-- Opens Lib's settings window, whose Hotkeys tab lists every module's hotkeys across every pack.
local openLibWindow = deps.openLibWindow

---@type table<string, string>
local overviewLabels = {}

---@param imgui table
---@param ownerId string
---@return boolean changed True when a row wrote a new binding.
return function(imgui, ownerId)
    local block = hotkeys.getOwnerBlock(ownerId)
    if block == nil then
        return false
    end
    imgui.Spacing()
    imgui.Separator()
    imgui.Text("Hotkeys")
    local changed = false
    for _, row in ipairs(block.rows) do
        if drawWidget(imgui, refForRow(row)) then
            changed = true
        end
    end
    local overviewLabel = overviewLabels[ownerId]
    if overviewLabel == nil then
        overviewLabel = "All hotkeys...##hotkeys-overview-" .. ownerId
        overviewLabels[ownerId] = overviewLabel
    end
    if imgui.Button(overviewLabel) then
        openLibWindow()
    end
    return changed
end
