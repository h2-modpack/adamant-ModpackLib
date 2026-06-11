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

local storage = import('core/storage/00_init.lua', nil, {
    logging = logging,
    values = values,
})

local hashingBundle = import('core/hashing/hashing.lua', nil, {
    storage = storage,
})

local moduleState = import('core/module_state/00_init.lua', nil, {
    chalk = externals.chalk,
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

local coordinator = import('core/coordinator/coordinator.lua', nil, {
    logging = logging,
    coordinatorRegistry = registry.coordinators,
})

local definition = import('core/module_bootstrap/definition.lua', nil, {
    plugin = externals.plugin,
    logging = logging,
    storage = storage,
    values = values,
    coordinator = coordinator,
    moduleRegistry = moduleRegistry,
})
local sharedBundle = import('core/shared/00_init.lua', nil, {
    logging = logging,
    sharedRegistry = registry.shared,
    moduleRegistry = moduleRegistry,
    values = values,
})
local shared = sharedBundle.service

local hooksBundle = import('core/hooks/00_init.lua', nil, {
    modutil = externals.modutil,
    logging = logging,
    moduleRegistry = moduleRegistry,
    hookRegistry = registry.hooks,
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
    moduleRegistry = moduleRegistry,
    rendererSystem = overlayRendererSystem,
    overlayRegistry = registry.overlays,
    values = values,
})
local overlays = overlaysBundle.service

local function createSystem(ownerId)
    return systemScope.create(ownerId, {
        hooks = hooksBundle.system,
        overlays = overlaysBundle.system,
    })
end

local mutationBundle = import('core/mutations/00_init.lua', nil, {
    gameDeps = gameDeps,
    logging = logging,
    values = values,
    moduleRegistry = moduleRegistry,
    coordinator = coordinator,
    mutationRegistry = registry.mutations,
})
local mutation = mutationBundle.service

local widgetsBundle = import('core/widgets/00_init.lua', nil, {
    logging = logging,
    storage = storage,
    actions = moduleState.actionBuffer,
    rom = externals.rom,
    controlsDraw = controlsBundle.draw,
})

local fallbackUiBundle = import('core/fallback/fallback_ui.lua', nil, {
    gameDeps = gameDeps,
    rom = externals.rom,
    modutil = externals.modutil,
    logging = logging,
    moduleRegistry = moduleRegistry,
    coordinator = coordinator,
    overlays = overlays,
    createSystem = createSystem,
    fallbackRegistry = registry.fallback,
})
local managedModule = import('core/module_bootstrap/managed_module.lua', nil, {
    logging = logging,
    definition = definition,
    moduleRegistry = moduleRegistry,
    moduleState = moduleState,
    shared = shared,
    cache = cacheBundle.service,
    sharedData = sharedBundle.data,
    hooks = hooks,
    overlays = overlays,
    mutation = mutation,
    fallbackUi = fallbackUiBundle.service,
    coordinator = coordinator,
    storage = storage,
    uiDraw = widgetsBundle.uiDraw,
    controls = controlsBundle,
})

local frameworkRuntime = import('core/lib_bootstrap/framework_runtime.lua', nil, {
    config = deps.config,
    logging = logging,
    hashing = hashingBundle.framework,
    coordinator = coordinator,
    managedModule = managedModule,
    overlays = overlaysBundle.framework,
})
public.createFrameworkRuntime = frameworkRuntime.create
local moduleBundle = import('core/module_bootstrap/module.lua', nil, {
    logging = logging,
    managedModule = managedModule,
    moduleState = moduleState,
    overlayOrder = overlaysBundle.order,
    hookDeclarations = hooksBundle.declarations,
    hookContext = hooksBundle.context,
    overlayDeclarations = overlaysBundle.declarations,
    sharedDataDeclarations = sharedBundle.dataDeclarations,
    sharedRegistrations = sharedBundle.registrations,
    mutationLifecycle = mutationBundle.lifecycle,
    fallbackUi = fallbackUiBundle.service,
    controlDeclarations = controlsBundle.declarations,
    controlCompiler = controlsBundle.compiler,
    statusDeclarations = statusDeclarations,
})
public.createModule = moduleBundle.public.createModule

return {
    coordinator = coordinator,
}
