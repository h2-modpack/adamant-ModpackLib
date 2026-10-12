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

local gameDeps = import('core/game_deps/game_deps.lua', nil, {
    rom = externals.rom,
    logging = logging,
})

local values = import('core/helpers/values.lua')
local receipt = import('core/helpers/receipt.lua')
local identifiers = import('core/helpers/identifiers.lua')
local requireMethodSelf = import('core/helpers/method_self.lua', nil, {
    logging = logging,
})

local storage = import('core/storage/00_init.lua', nil, {
    logging = logging,
    values = values,
    identifiers = identifiers,
})

local moduleState = import('core/module_state/00_init.lua', nil, {
    logging = logging,
    rom = externals.rom,
    storage = storage,
    values = values,
    requireMethodSelf = requireMethodSelf,
})

local cacheBundle = import('core/cache/00_init.lua', nil, {
    logging = logging,
    gameDeps = gameDeps,
})

local controlsBundle = import('core/controls/00_init.lua', nil, {
    logging = logging,
    values = values,
    storage = storage,
    identifiers = identifiers,
    requireMethodSelf = requireMethodSelf,
})

local statusDeclarations = import('core/status/declarations.lua', nil, {
    logging = logging,
    values = values,
    identifiers = identifiers,
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
    identifiers = identifiers,
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
-- Capability installs activation runs for every module, in install order. Commit order comes
-- from each receipt's phase; `install` returns nil when the module declares nothing for it.
---@type AdamantModpackLib.ModuleCapability[]
local moduleCapabilities = {
    {
        name = "shared",
        install = function(ownerId, _, inputs)
            return sharedBundle.install(ownerId, inputs.shared)
        end,
    },
    {
        name = "hooks",
        install = function(ownerId, owner, inputs)
            return hooks.install(ownerId, owner, inputs.hookDeclarations)
        end,
    },
    {
        name = "overlays",
        install = function(ownerId, owner, inputs)
            return overlays.install(ownerId, {
                owner = owner,
                declarations = inputs.overlays.declarations,
                host = inputs.overlays.host,
                runtime = inputs.overlays.runtime,
            })
        end,
    },
    {
        name = "mutation",
        install = function(_, _, inputs)
            return inputs.mutation.sync()
        end,
    },
    {
        name = "fallbackUi",
        install = function(ownerId, owner, inputs)
            if not inputs.fallbackUiRequested then
                return nil
            end
            return fallbackUi.install(ownerId, owner)
        end,
    },
}
local moduleActivation = import('core/module_bootstrap/managed_module_activation.lua', nil, {
    logging = logging,
    coordinator = modpackCoordination,
    moduleRegistry = moduleRegistry,
    capabilities = moduleCapabilities,
})
local managedModule = import('core/module_bootstrap/managed_module.lua', nil, {
    logging = logging,
    moduleRegistry = moduleRegistry,
    moduleActivation = moduleActivation,
    moduleState = moduleState,
    shared = sharedBundle,
    cache = cacheBundle,
    hookDeclarations = hooksBundle.declarations,
    overlays = overlays,
    mutation = mutation,
    uiDraw = widgetsBundle.uiDraw,
    controlRefs = controlsBundle.refs,
})

public.modpack = import('core/modpack/init.lua', nil, {
    rom = externals.rom,
    libConfig = deps.config,
    storage = storage,
    coordination = modpackCoordination,
    overlaySurface = overlaysBundle.modpack,
    getLiveModule = moduleRegistry.getLiveModule,
    packRegistry = registry.modpacks,
})
local moduleBundle = import('core/module_bootstrap/module.lua', nil, {
    logging = logging,
    managedModule = managedModule,
    definition = definition,
    moduleRegistry = moduleRegistry,
    moduleState = moduleState,
    overlayAuthoring = overlaysBundle.authoring,
    hookDeclarations = hooksBundle.declarations,
    hookContext = hooksBundle.context,
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
