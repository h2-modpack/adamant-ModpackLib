local deps = ...
local externals = deps.externals

AdamantModpackLib_Runtime = AdamantModpackLib_Runtime or {}
local runtimeRoot = AdamantModpackLib_Runtime

local logging = import('core/logging/logging.lua', nil, {
    config = deps.config,
})

local registry = import('core/lib_bootstrap/registry.lua', nil, {
    runtimeRoot = runtimeRoot,
})
local moduleRegistry = import('core/lib_bootstrap/module_registry.lua', nil, {
    moduleBucket = registry.modules,
})
local systemScope = import('core/lib_bootstrap/system_scope.lua', nil, {
    logging = logging,
})

local gameDeps = externals.gameDeps or import('core/game_deps/game_deps.lua', nil, {
    rom = externals.rom,
    logging = logging,
})

local values = import('core/helpers/values.lua')
local receipt = import('core/helpers/receipt.lua')

local storage = import('core/storage/00_init.lua', nil, {
    logging = logging,
    values = values,
})

local moduleState = import('core/module_state/00_init.lua', nil, {
    logging = logging,
    rom = externals.rom,
    storage = storage,
    values = values,
})

local cacheBundle = import('core/cache/00_init.lua', nil, {
    logging = logging,
    gameDeps = gameDeps,
})

local controlsBundle = import('core/controls/00_init.lua', nil, {
    logging = logging,
    values = values,
    storage = storage,
})

local statusDeclarations = import('core/status/declarations.lua', nil, {
    logging = logging,
    values = values,
})

local modpackCoordination = import('core/coordination/coordination.lua', nil, {
    logging = logging,
    coordinationRegistry = registry.coordinators,
})

local definition = import('core/module_bootstrap/definition.lua', nil, {
    plugin = externals.plugin,
    logging = logging,
    storage = storage,
    values = values,
    coordinator = modpackCoordination,
})
local sharedBundle = import('core/shared/00_init.lua', nil, {
    logging = logging,
    sharedRegistry = registry.shared,
    values = values,
    receipt = receipt,
})

local hooksBundle = import('core/hooks/00_init.lua', nil, {
    modutil = externals.modutil,
    logging = logging,
    hookRegistry = registry.hooks,
    receipt = receipt,
})
local hooks = hooksBundle.service

local overlayRendererSystem = systemScope.create("adamant-lib.overlays.renderer", {
    hooks = hooksBundle.system,
})
local overlaysBundle = import('core/overlays/00_init.lua', nil, {
    gameDeps = gameDeps,
    rom = externals.rom,
    logging = logging,
    hooks = hooks,
    hookDeclarations = hooksBundle.declarations,
    rendererSystem = overlayRendererSystem,
    overlayRegistry = registry.overlays,
    values = values,
    receipt = receipt,
})
local overlays = overlaysBundle.service

local function createSystem(ownerId)
    return systemScope.create(ownerId, {
        hooks = hooksBundle.system,
        overlays = overlaysBundle.system,
    })
end

local mutation = import('core/mutations/00_init.lua', nil, {
    gameDeps = gameDeps,
    logging = logging,
    values = values,
    mutationRegistry = registry.mutations,
    receipt = receipt,
})

local widgetsBundle = import('core/widgets/00_init.lua', nil, {
    logging = logging,
    storage = storage,
    isDrawActionRef = moduleState.isDrawActionRef,
    rom = externals.rom,
    controlsDraw = controlsBundle.draw,
})

local createTheme = import('core/ui/theme.lua', nil, {
    rom = externals.rom,
})

local fallbackUi = import('core/fallback/fallback_ui.lua', nil, {
    createTheme = createTheme,
    gameDeps = gameDeps,
    rom = externals.rom,
    modutil = externals.modutil,
    logging = logging,
    coordination = modpackCoordination,
    overlays = overlays,
    createSystem = createSystem,
    fallbackRegistry = registry.fallback,
    receipt = receipt,
})
local managedModule = import('core/module_bootstrap/managed_module.lua', nil, {
    logging = logging,
    definition = definition,
    moduleRegistry = moduleRegistry,
    moduleState = moduleState,
    shared = sharedBundle,
    cache = cacheBundle,
    hooks = hooks,
    hookDeclarations = hooksBundle.declarations,
    overlays = overlays,
    mutation = mutation,
    fallbackUi = fallbackUi,
    coordinator = modpackCoordination,
    storage = storage,
    uiDraw = widgetsBundle.uiDraw,
    controls = controlsBundle,
})

public.modpack = import('core/modpack/init.lua', nil, {
    rom = externals.rom,
    libConfig = deps.config,
    storage = storage,
    coordination = modpackCoordination,
    overlaySurface = overlaysBundle.modpack.create(),
    getLiveModule = managedModule.getLiveModule,
    packRegistry = registry.modpacks,
})
local moduleBundle = import('core/module_bootstrap/module.lua', nil, {
    logging = logging,
    managedModule = managedModule,
    moduleState = moduleState,
    overlayOrder = overlaysBundle.order,
    overlayRegions = overlaysBundle.regions,
    overlayFonts = overlaysBundle.fonts,
    hookDeclarations = hooksBundle.declarations,
    hookContext = hooksBundle.context,
    overlayDeclarations = overlaysBundle.declarations,
    sharedDataDeclarations = sharedBundle.dataDeclarations,
    sharedRegistrations = sharedBundle.registrations,
    mutationLifecycle = mutation,
    fallbackUi = fallbackUi,
    controlDeclarations = controlsBundle.declarations,
    controlCompiler = controlsBundle.compiler,
    statusDeclarations = statusDeclarations,
})
public.createModule = moduleBundle.public.createModule

return {
    modpackCoordination = modpackCoordination,
}
