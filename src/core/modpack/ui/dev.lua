local ctx = ...

local rom = ctx.rom
local ui = rom.ImGui
local config = ctx.config
local colors = ctx.colors
local moduleRegistry = ctx.moduleRegistry
local staging = ctx.staging
local runtime = ctx.runtime
local frameworkRuntime = ctx.frameworkRuntime

local function TextColored(imgui, color, text)
    imgui.TextColored(color[1], color[2], color[3], color[4], text)
end

local function draw(snapshot)
    TextColored(ui, colors.info, "Developer options for module authors and debugging.")
    ui.Spacing()

    -- Framework debug gates framework-owned warnings such as module indexing, hash import,
    -- and framework-managed runtime mutation failures.
    -- Load-time schema validation lives in Lib.
    -- Read/write directly from config - intentional exception to the staging pattern.
    local fwVal, fwChg = ui.Checkbox("Framework Debug", config.DebugMode == true)
    if fwChg then
        config.DebugMode = fwVal
    end
    if ui.IsItemHovered() then
        ui.SetTooltip(
        "Print framework diagnostics for module indexing, hash parsing, and runtime mutation failures.")
    end

    local libVal, libChg = ui.Checkbox("Lib Debug", frameworkRuntime.diagnostics.isLibDebugEnabled())
    if libChg then
        frameworkRuntime.diagnostics.setLibDebugEnabled(libVal)
    end
    if ui.IsItemHovered() then
        ui.SetTooltip(
        "Print lib-internal diagnostic warnings (schema errors, unknown field types). Shared across all packs.")
    end

    if ui.Button("Resync State") then
        runtime.resyncAllState()
    end

    TextColored(ui, colors.info, "Per-Module Debug")
    ui.Spacing()

    for _, entry in ipairs(moduleRegistry.modules) do
        local val, chg = ui.Checkbox(entry._debugLabel, staging.debug[entry.id])
        if chg then
            staging.debug[entry.id] = val
            moduleRegistry.snapshot.setDebugEnabled(entry, val, snapshot)
        end
    end
end

return draw
