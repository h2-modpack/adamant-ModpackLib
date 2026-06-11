local deps = ...
local rom = deps.rom
local frameworkRuntime = deps.frameworkRuntime
local packRegistry = deps.packRegistry

local logging = import "core/modpack/logging.lua"
local hashCodec = import "core/modpack/hash/codec.lua"
local createTheme = import("core/modpack/ui/theme.lua", nil, {
    rom = rom,
})
local createModuleRegistry = import("core/modpack/modules/registry.lua", nil, {
    rom = rom,
    logging = logging,
})
local profileTools = import("core/modpack/profiles/audit.lua", nil, {
    hashCodec = hashCodec,
    logging = logging,
})
local createConfigHash = import("core/modpack/hash/config_hash.lua", nil, {
    rom = rom,
    hashCodec = hashCodec,
    logging = logging,
})
local createHud = import("core/modpack/hud/runtime.lua")
local createUI = import("core/modpack/ui/window.lua", nil, {
    rom = rom,
    logging = logging,
})

local constructors = {
    createModuleRegistry = createModuleRegistry,
    createConfigHash = createConfigHash,
    createHud = createHud,
    createUI = createUI,
    createTheme = createTheme,
}

return import("core/modpack/pack_bootstrap.lua", nil, {
    rom = rom,
    logging = logging,
    profileTools = profileTools,
    constructors = constructors,
    frameworkRuntime = frameworkRuntime,
    packRegistry = packRegistry,
})
