-- =============================================================================
-- ADAMANT-LIB: Shared utilities for adamant standalone mods
-- =============================================================================
-- Access via: local lib = rom.mods['adamant-ModpackLib']

local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN

modutil = mods['SGG_Modding-ModUtil']
local chalk = mods['SGG_Modding-Chalk']
local libConfig = chalk.auto('config.lua')
public.config = libConfig

local _coordinators = {}
local _coordinatorRebuilds = {}
local _liveModuleHosts = {}
local _liveModuleHostsByPack = {}
AdamantModpackLib_Internal = AdamantModpackLib_Internal or {}
local internal = AdamantModpackLib_Internal
internal.libConfig = libConfig
internal.coordinators = _coordinators
internal.coordinatorRebuilds = _coordinatorRebuilds
internal.liveModuleHosts = internal.liveModuleHosts or _liveModuleHosts
internal.liveModuleHostsByPack = internal.liveModuleHostsByPack or _liveModuleHostsByPack
internal.pendingCoordinatorRebuilds = internal.pendingCoordinatorRebuilds
    or setmetatable({}, { __mode = "k" })
internal.logging = internal.logging or {}
local fallbackHud = import 'core/private/fallback_hud.lua'

---@class AdamantModpackLib
---@field config table
---@field createStore fun(modConfig: table, definition: ModuleDefinition, dataDefaults: table|nil): ManagedStore, Session
---@field resetStorageToDefaults fun(storage: StorageSchema, session: Session, opts: table|nil)
---@field createModuleHost fun(opts: ModuleHostOpts): ModuleHost
---@field standaloneHost fun(packId: string|nil, moduleIdOrOpts: string|StandaloneOpts|nil, opts: StandaloneOpts|nil): StandaloneRuntime
---@field getLiveModuleHost fun(moduleName: string|nil): ModuleHost|nil
---@field getLiveModuleHostById fun(packId: string|nil, moduleId: string|nil): ModuleHost|nil
---@field isModuleCoordinated fun(packId: string|nil): boolean
---@field isModuleEnabled fun(store: ManagedStore, packId: string|nil): boolean
---@field lifecycle table
---@field mutation table
---@field logging table
---@field hashing table
---@field imguiHelpers table
---@field widgets table
---@field nav table

import 'core/init.lua'
import 'widgets/init.lua'

-- Standalone framework debug toggle - hidden when Core/Framework registers coordinators.
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

modutil.once_loaded.game(function()
    fallbackHud.createMarker()
end)
