-- =============================================================================
-- ADAMANT-LIB: Shared utilities for adamant mods
-- =============================================================================
-- Access via: local lib = rom.mods['adamant-ModpackLib']

local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN

local modutil = mods['SGG_Modding-ModUtil']
local chalk = mods['SGG_Modding-Chalk']
local libConfig = chalk.auto('config.lua')

local externals = {
    rom = rom,
    chalk = chalk,
    plugin = _PLUGIN,
    modutil = modutil,
}

local core = import('core/init.lua', nil, {
    config = libConfig,
    externals = externals,
})

-- Fallback framework debug toggle - hidden when Core/Framework registers coordinators.
rom.gui.add_to_menu_bar(function()
    if core.coordinator.hasRegistrations() then return end
    if rom.ImGui.BeginMenu("adamant-lib") then
        local val, chg = rom.ImGui.Checkbox("Lib Debug", libConfig.DebugMode == true)
        if chg then libConfig.DebugMode = val end
        if rom.ImGui.IsItemHovered() then
            rom.ImGui.SetTooltip("Print lib-internal diagnostic warnings. Structural schema errors always fail.")
        end
        rom.ImGui.EndMenu()
    end
end)
