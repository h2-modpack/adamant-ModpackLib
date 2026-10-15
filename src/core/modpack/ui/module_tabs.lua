local ctx = ...

local ui = ctx.rom.ImGui
local drawHotkeyBlock = ctx.drawHotkeyBlock
local staging = ctx.staging
local runtime = ctx.runtime
local snapshotAccess = ctx.snapshotAccess

local function drawEntryBody(entry, snapshot)
    local liveModule = snapshotAccess.getLiveModule(entry, snapshot)
    if not liveModule then
        return
    end

    liveModule.drawTab()

    runtime.commitEntryState(entry, snapshot)
end

local function draw(entry, snapshot)
    local enabled = staging.modules[entry.id] or false
    local val, chg = ui.Checkbox(entry._enableLabel, enabled)
    if chg then
        local ok = runtime.toggleEntry(entry, val, snapshot)
        if ok then
            enabled = val == true
        end
    end
    if ui.IsItemHovered() and entry.tooltip then
        ui.SetTooltip(entry.tooltip)
    end

    -- Lib-owned hotkey block: shown while disabled too, so bindings stay editable (state "disabled").
    drawHotkeyBlock(ui, entry.pluginGuid)

    if not enabled then return end

    ui.Spacing()
    drawEntryBody(entry, snapshot)
end

return draw
