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
    if core.modpackCoordination.hasRegistrations() then return end
    if rom.ImGui.BeginMenu("adamant-lib") then
        local val, chg = rom.ImGui.Checkbox("Lib Policy Debug", libConfig.DebugMode == true)
        if chg then libConfig.DebugMode = val end

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
            local diagVal, diagChg = rom.ImGui.Checkbox(
                diagnostic.label,
                diagnostic.enabled == true
            )
            if diagChg then diagnostic.enabled = diagVal end
        end
        rom.ImGui.EndMenu()
    end
end)
