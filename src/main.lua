-- =============================================================================
-- ADAMANT-LIB: Shared utilities for adamant standalone mods
-- =============================================================================
-- Access via: local lib = rom.mods['adamant-ModpackLib']

local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN

local chalk = mods['SGG_Modding-Chalk']
local libConfig = chalk.auto('config.lua')
public.config = libConfig

local _coordinators = {}
AdamantModpackLib_Internal = AdamantModpackLib_Internal or {}
local internal = AdamantModpackLib_Internal
internal.libConfig    = libConfig
internal.coordinators = _coordinators
internal.logging      = internal.logging or {}

import 'core/init.lua'
import 'widgets/init.lua'

-- Standalone framework debug toggle — hidden when Core is installed.
---@diagnostic disable-next-line: redundant-parameter
rom.gui.add_to_menu_bar(function()
    if next(_coordinators) ~= nil then return end
    if rom.ImGui.BeginMenu("adamant-lib") then
        local val, chg = rom.ImGui.Checkbox("Lib Debug", libConfig.DebugMode == true)
        if chg then libConfig.DebugMode = val end
        if rom.ImGui.IsItemHovered() then
            rom.ImGui.SetTooltip("Print lib-internal diagnostic warnings (schema errors, unknown field types)")
        end
        rom.ImGui.EndMenu()
    end
end)
