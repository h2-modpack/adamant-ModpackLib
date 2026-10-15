-- Lib-owned "Hotkeys" block in every module's standard header, drawn right after the
-- Enabled/Debug row by the modpack module tab and the fallback window. Modules without hotkey
-- requests draw nothing.
--
-- The block collapses to its summary line while every request is active, unbound or disabled, and
-- opens itself when a request needs attention (conflict, reserved, invalid). The user can toggle
-- it; that choice holds until the attention state changes. Open state is UI memory only.
--
-- The draw path allocates nothing per frame: the summary is built by the registry when resolution
-- runs, and the header label is rebuilt only when the summary string changes.

local deps = ...

local drawWidget = deps.drawWidget
local hotkeys = deps.hotkeys
local refForRow = deps.refForRow

local HEADER_ID_PREFIX = "###hotkeys-block-"

---@type table<string, { attention: boolean?, open: boolean, summary: string?, label: string? }>
local memory = {}

local function memoryFor(ownerId, block)
    local entry = memory[ownerId]
    if entry == nil then
        entry = { attention = nil, open = false, summary = nil, label = nil }
        memory[ownerId] = entry
    end
    if entry.attention ~= block.attention then
        entry.attention = block.attention
        entry.open = block.attention
    end
    if entry.summary ~= block.summary then
        entry.summary = block.summary
        entry.label = block.summary .. HEADER_ID_PREFIX .. ownerId
    end
    return entry
end

-- CollapsingHeader with SetNextItemOpen lets Lib drive the open state; without them (older
-- bindings) the block is always expanded under a plain summary line.
local function drawHeader(imgui, entry)
    if imgui.CollapsingHeader == nil or imgui.SetNextItemOpen == nil then
        imgui.Text(entry.summary)
        return true
    end
    imgui.SetNextItemOpen(entry.open)
    entry.open = imgui.CollapsingHeader(entry.label) == true
    return entry.open
end

---@param imgui table
---@param ownerId string
---@return boolean changed True when a row wrote a new binding.
return function(imgui, ownerId)
    local block = hotkeys.getOwnerBlock(ownerId)
    if block == nil then
        return false
    end
    imgui.Spacing()
    local entry = memoryFor(ownerId, block)
    if not drawHeader(imgui, entry) then
        return false
    end
    local changed = false
    for _, row in ipairs(block.rows) do
        if drawWidget(imgui, refForRow(row)) then
            changed = true
        end
    end
    return changed
end
