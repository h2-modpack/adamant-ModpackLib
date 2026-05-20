local deps = ...
local externals = deps.externals

AdamantModpackLib_Runtime = AdamantModpackLib_Runtime or {}
local runtime = AdamantModpackLib_Runtime

local logging = import('core/logging/logging.lua', nil, {
    config = deps.config,
})

local moduleRuntimeRegistry = import('core/lib_bootstrap/runtime_registry.lua', nil, {
    runtime = runtime,
})
local hostState = import('core/lib_bootstrap/module_host_state.lua', nil, {
    moduleHostStateStore = moduleRuntimeRegistry.getModuleHostStateStore(),
})
local systemScope = import('core/lib_bootstrap/system_scope.lua', nil, {
    logging = logging,
})

local gameDeps = externals.gameDeps or import('core/game_deps/game_deps.lua', nil, {
    rom = externals.rom,
    logging = logging,
})

local values = import('core/helpers/values.lua')

local storage = import('core/storage/storage.lua', nil, {
    logging = logging,
    values = values,
})

local hashingBundle = import('core/hashing/hashing.lua', nil, {
    storage = storage,
})
public.hashing = nil

local moduleState = import('core/module_state/module_state.lua', nil, {
    chalk = externals.chalk,
    logging = logging,
    storage = storage,
    values = values,
})
public.resetStorageToDefaults = nil

local gameCacheBundle = import('core/game_cache/game_cache.lua', nil, {
    logging = logging,
    gameDeps = gameDeps,
    hostState = hostState,
})
public.gameCache = nil

local coordinator = import('core/coordinator/coordinator.lua', nil, {
    logging = logging,
    runtime = runtime,
})


local definition = import('core/module_bootstrap/definition.lua', nil, {
    plugin = externals.plugin,
    logging = logging,
    storage = storage,
    values = values,
    coordinator = coordinator,
    moduleRuntimeRegistry = moduleRuntimeRegistry,
})
local integrationsBundle = import('core/integrations/integrations.lua', nil, {
    logging = logging,
    runtime = runtime,
    hostState = hostState,
})
local integrations = integrationsBundle.service
public.integrations = nil
local hooksBundle = import('core/hooks/hooks.lua', nil, {
    modutil = externals.modutil,
    logging = logging,
    hostState = hostState,
    runtime = runtime,
})
local hooks = hooksBundle.service
public.hooks = nil
local overlayRendererSystem = systemScope.create("adamant-lib.overlays.renderer", {
    hooks = hooksBundle.system,
})
local overlaysBundle = import('core/overlays/overlays.lua', nil, {
    gameDeps = gameDeps,
    rom = externals.rom,
    logging = logging,
    hooks = hooks,
    hostState = hostState,
    rendererSystem = overlayRendererSystem,
    runtime = runtime,
    values = values,
})
local overlays = overlaysBundle.service
public.overlays = nil
local function createSystem(ownerId)
    return systemScope.create(ownerId, {
        hooks = hooksBundle.system,
        overlays = overlaysBundle.system,
    })
end
public.createSystem = nil
local mutationBundle = import('core/mutations/mutations.lua', nil, {
    gameDeps = gameDeps,
    logging = logging,
    values = values,
    hostState = hostState,
    coordinator = coordinator,
    runtime = runtime,
})
local mutation = mutationBundle.service
public.mutation = nil
local widgetsBundle = import('core/widgets/init.lua', nil, {
    logging = logging,
    storage = storage,
    actions = moduleState.actions,
})
public.widgets = nil
public.nav = nil
public.imguiHelpers = nil
local fallbackUiBundle = import('core/fallback/fallback_ui.lua', nil, {
    gameDeps = gameDeps,
    rom = externals.rom,
    modutil = externals.modutil,
    logging = logging,
    hostState = hostState,
    coordinator = coordinator,
    overlays = overlays,
    createSystem = createSystem,
    runtime = runtime,
})
local authorHost = import('core/module_bootstrap/author_host.lua', nil, {
    fallbackUi = fallbackUiBundle.author,
    gameCache = gameCacheBundle.author,
    hooks = hooksBundle.author,
    integrations = integrationsBundle.author,
    mutation = mutationBundle.author,
    overlays = overlaysBundle.author,
})
local moduleHost = import('core/module_bootstrap/host.lua', nil, {
    logging = logging,
    values = values,
    definition = definition,
    hostState = hostState,
    moduleRuntimeRegistry = moduleRuntimeRegistry,
    moduleState = moduleState,
    integrations = integrations,
    hooks = hooks,
    overlays = overlays,
    mutation = mutation,
    fallbackUi = fallbackUiBundle.service,
    coordinator = coordinator,
    storage = storage,
    widgets = widgetsBundle.widgets,
    nav = widgetsBundle.nav,
    authorHost = authorHost,
})
public.getLiveModuleHost = nil
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
