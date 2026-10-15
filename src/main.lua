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

-- Lib menu, shown with or without packs. Its one item opens Lib's settings window (Hotkeys for
-- every module across every pack, reserved keys, Lib debug toggles).
rom.gui.add_to_menu_bar(function()
    if rom.ImGui.BeginMenu("adamant-lib") then
        if rom.ImGui.MenuItem("Settings") then
            core.libWindow.open()
        end
        rom.ImGui.EndMenu()
    end
end)
