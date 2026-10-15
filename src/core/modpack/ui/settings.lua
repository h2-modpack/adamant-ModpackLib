-- Pack Settings page: Modpack Debug and a projection of this pack's modules' hotkeys. Rows use
-- Lib's hotkey widget and edit path; a conflict with another pack's module names that owner in the
-- row's status line. Lib's settings window owns the full hotkey list and the reserved-key editor.

local ctx = ...

local ui = ctx.rom.ImGui
local config = ctx.config
local colors = ctx.colors
local moduleRegistry = ctx.moduleRegistry
local hotkeyOverview = ctx.hotkeyOverview
local openLibWindow = ctx.openLibWindow

local function TextColored(imgui, color, text)
    imgui.TextColored(color[1], color[2], color[3], color[4], text)
end

-- Owner ids of this pack's modules, rebuilt when the module registry refreshes its list.
local ownerIds = {}
local ownerIdsSource = nil

local function packOwnerIds()
    local modules = moduleRegistry.modules
    if ownerIdsSource ~= modules then
        ownerIds = {}
        for _, entry in ipairs(modules) do
            ownerIds[entry.pluginGuid] = true
        end
        ownerIdsSource = modules
    end
    return ownerIds
end

local function draw()
    -- Modpack debug gates modpack-owned warnings such as module indexing, hash import,
    -- and modpack-managed runtime mutation failures.
    -- Read/write directly from config - intentional exception to the staging pattern.
    local fwVal, fwChg = ui.Checkbox("Modpack Debug", config.DebugMode == true)
    if fwChg then
        config.DebugMode = fwVal
    end
    if ui.IsItemHovered() then
        ui.SetTooltip(
        "Print modpack diagnostics for module indexing, hash parsing, and runtime mutation failures.")
    end

    ui.Spacing()
    ui.Separator()
    TextColored(ui, colors.info, "Hotkeys")
    ui.Spacing()
    hotkeyOverview.drawForOwners(ui, colors, packOwnerIds())
    ui.Spacing()
    hotkeyOverview.drawDetectedKey(ui)
    if ui.Button("All hotkeys...##pack-settings") then
        openLibWindow()
    end
end

return draw
