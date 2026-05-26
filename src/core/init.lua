local deps = ...
local externals = deps.externals

AdamantModpackLib_Runtime = AdamantModpackLib_Runtime or {}
local runtimeRoot = AdamantModpackLib_Runtime

local logging = import('core/logging/logging.lua', nil, {
    config = deps.config,
})
local phaseGate = import('core/module_bootstrap/ui/phase_gate.lua', nil, {
    logging = logging,
})

local registry = import('core/lib_bootstrap/registry.lua', nil, {
    runtimeRoot = runtimeRoot,
})
local hostRegistry = import('core/lib_bootstrap/host_registry.lua', nil, {
    hostBucket = registry.hosts,
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
    storage = storage,
    values = values,
    phaseGate = phaseGate,
})

local cacheBundle = import('core/cache/00_init.lua', nil, {
    logging = logging,
    gameDeps = gameDeps,
    hostRegistry = hostRegistry,
    cacheRegistry = registry.cache,
    values = values,
    phaseGate = phaseGate,
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
    hostRegistry = hostRegistry,
})
local integrationsBundle = import('core/integrations/00_init.lua', nil, {
    logging = logging,
    storage = storage,
    integrationRegistry = registry.integrations,
    hostRegistry = hostRegistry,
})
local integrations = integrationsBundle.service

local hooksBundle = import('core/hooks/00_init.lua', nil, {
    modutil = externals.modutil,
    logging = logging,
    hostRegistry = hostRegistry,
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
    hostRegistry = hostRegistry,
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
    hostRegistry = hostRegistry,
    coordinator = coordinator,
    mutationRegistry = registry.mutations,
})
local mutation = mutationBundle.service

local widgetsBundle = import('core/widgets/00_init.lua', nil, {
    logging = logging,
    storage = storage,
    actions = moduleState.actionBuffer,
    rom = externals.rom,
    phaseGate = phaseGate,
})

local fallbackUiBundle = import('core/fallback/fallback_ui.lua', nil, {
    gameDeps = gameDeps,
    rom = externals.rom,
    modutil = externals.modutil,
    logging = logging,
    hostRegistry = hostRegistry,
    coordinator = coordinator,
    overlays = overlays,
    createSystem = createSystem,
    fallbackRegistry = registry.fallback,
})
local authorHost = import('core/module_bootstrap/author_host.lua', nil, {
    fallbackUi = fallbackUiBundle.author,
    hooks = hooksBundle.author,
    integrations = integrationsBundle.author,
    mutation = mutationBundle.author,
    overlays = overlaysBundle.author,
})
local moduleHost = import('core/module_bootstrap/host.lua', nil, {
    logging = logging,
    definition = definition,
    hostRegistry = hostRegistry,
    moduleState = moduleState,
    integrations = integrations,
    cache = cacheBundle.service,
    hooks = hooks,
    overlays = overlays,
    mutation = mutation,
    fallbackUi = fallbackUiBundle.service,
    coordinator = coordinator,
    storage = storage,
    uiDraw = widgetsBundle.uiDraw,
    authorHost = authorHost,
    phaseGate = phaseGate,
})

local frameworkRuntime = import('core/lib_bootstrap/framework_runtime.lua', nil, {
    config = deps.config,
    logging = logging,
    hashing = hashingBundle.framework,
    coordinator = coordinator,
    moduleHost = moduleHost,
    overlays = overlaysBundle.framework,
})
public.createFrameworkRuntime = frameworkRuntime.create
local moduleBundle = import('core/module_bootstrap/module.lua', nil, {
    logging = logging,
    moduleHost = moduleHost,
    moduleState = moduleState,
})
public.createModule = moduleBundle.public.createModule

return {
    coordinator = coordinator,
}
