local ctx = ...

local rom = ctx.rom
local ui = rom.ImGui
local config = ctx.config
local libConfig = ctx.libConfig
local colors = ctx.colors
local moduleRegistry = ctx.moduleRegistry
local staging = ctx.staging
local runtime = ctx.runtime

local function TextColored(imgui, color, text)
    imgui.TextColored(color[1], color[2], color[3], color[4], text)
end

local function draw(snapshot)
    TextColored(ui, colors.info, "Developer options for module authors and debugging.")
    ui.Spacing()

    -- Modpack debug gates modpack-owned warnings such as module indexing, hash import,
    -- and modpack-managed runtime mutation failures.
    -- Load-time schema validation lives in Lib.
    -- Read/write directly from config - intentional exception to the staging pattern.
    local fwVal, fwChg = ui.Checkbox("Modpack Debug", config.DebugMode == true)
    if fwChg then
        config.DebugMode = fwVal
    end
    if ui.IsItemHovered() then
        ui.SetTooltip(
        "Print modpack diagnostics for module indexing, hash parsing, and runtime mutation failures.")
    end

    local libVal, libChg = ui.Checkbox("Lib Policy Debug", libConfig.DebugMode == true)
    if libChg then
        libConfig.DebugMode = libVal
    end
    if ui.IsItemHovered() then
        ui.SetTooltip(
        "Print lib debug-policy warnings. Shared across all packs.")
    end

    local diagnostics = libConfig.Diagnostics
    local diagnosticKeys = {}
    for key, diagnostic in pairs(diagnostics) do
        if type(diagnostic) == "table" then
            diagnosticKeys[#diagnosticKeys + 1] = key
        end
    end
    table.sort(diagnosticKeys)

    for _, key in ipairs(diagnosticKeys) do
        local diagnostic = diagnostics[key]
        local diagVal, diagChg = ui.Checkbox(diagnostic.label, diagnostic.enabled == true)
        if diagChg then
            diagnostic.enabled = diagVal
        end
    end

    if ui.Button("Resync State") then
        runtime.resyncAllState()
    end

    TextColored(ui, colors.info, "Per-Module Debug")
    ui.Spacing()

    for _, entry in ipairs(moduleRegistry.modules) do
        local val, chg = ui.Checkbox(entry._debugLabel, staging.debug[entry.id])
        if chg then
            local ok = moduleRegistry.snapshot.setDebugEnabled(entry, val, snapshot)
            if ok then
                staging.debug[entry.id] = val
            end
        end
    end
end

return draw
