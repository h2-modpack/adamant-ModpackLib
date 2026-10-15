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

import('core/init.lua', nil, {
    config = libConfig,
    externals = externals,
})

-- The `adamant-lib` menu and Lib's settings window register themselves once per process
-- (core/ui/lib_window.lua).
