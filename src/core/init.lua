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
local hotkeyBindings = import('core/hotkeys/bindings.lua')

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

local hotkeys = import('core/hotkeys/00_init.lua', nil, {
    logging = logging,
    receipt = receipt,
    rom = externals.rom,
    libConfig = deps.config,
    bindings = hotkeyBindings,
    hotkeyRegistry = registry.hotkeys,
})
local statusColors = import('core/ui/status_colors.lua')
local hotkeyWidget = import('core/hotkeys/widget.lua', nil, {
    bindings = hotkeyBindings,
    hotkeys = hotkeys,
    statusColors = statusColors,
})
local hotkeyRowRef = import('core/hotkeys/row_refs.lua', nil, {
    logging = logging,
    hotkeys = hotkeys,
    getLiveModule = moduleRegistry.getLiveModule,
})
local createTheme = import('core/ui/theme.lua', nil, {
    rom = externals.rom,
})

-- Lib-drawn hotkey UI: the overview pieces (Lib settings window, pack Settings pages) and the
-- hotkey section of every module's Hotkeys & Advanced tab.
local hotkeyOverview = import('core/hotkeys/overview.lua', nil, {
    hotkeys = hotkeys,
    drawWidget = hotkeyWidget.draw,
    refForRow = hotkeyRowRef,
})
local libWindow = import('core/ui/lib_window.lua', nil, {
    rom = externals.rom,
    createTheme = createTheme,
    drawHotkeys = hotkeyOverview.drawAll,
    libConfig = deps.config,
    uiRegistry = registry.ui,
})
local drawHotkeyBlock = import('core/hotkeys/module_block.lua', nil, {
    hotkeys = hotkeys,
    drawWidget = hotkeyWidget.draw,
    refForRow = hotkeyRowRef,
    openLibWindow = libWindow.openHotkeys,
})
-- One module frame (Enabled, header, module tabs, Hotkeys & Advanced) shared by pack module pages
-- and fallback windows.
local createModuleFrame = import('core/ui/module_frame.lua', nil, {
    hotkeys = hotkeys,
    drawHotkeyBlock = drawHotkeyBlock,
    statusColors = statusColors,
    imguiCol = import('core/widgets/imgui_helpers.lua').ImGuiCol,
})
local hotkeyDeclarations = import('core/hotkeys/declarations.lua', nil, {
    logging = logging,
    identifiers = identifiers,
    bindings = hotkeyBindings,
})

local draw = import('core/widgets/00_init.lua', nil, {
    logging = logging,
    storage = storage,
    isDrawActionRef = moduleState.isDrawActionRef,
    rom = externals.rom,
    controlsDraw = controlsBundle.draw,
})

local uiSession = import('core/ui/session.lua')

local fallbackUi = import('core/fallback/fallback_ui.lua', nil, {
    createTheme = createTheme,
    uiSession = uiSession,
    gameDeps = gameDeps,
    rom = externals.rom,
    modutil = externals.modutil,
    logging = logging,
    coordination = modpackCoordination,
    overlays = overlays,
    createSystem = createSystem,
    fallbackRegistry = registry.fallback,
    receipt = receipt,
    createModuleFrame = createModuleFrame,
})
-- Capability installs activation runs for every module, in install order. Commit order comes
-- from each receipt's phase; an install returns nil when the module declares nothing for it.
---@type AdamantModpackLib.ModuleCapabilityInstall[]
local moduleCapabilities = {
    function(ownerId, _, inputs)
        return sharedBundle.install(ownerId, inputs.shared)
    end,
    function(ownerId, owner, inputs)
        return hooks.install(ownerId, owner, inputs.hookDeclarations)
    end,
    function(ownerId, owner, inputs)
        return overlays.install(ownerId, {
            owner = owner,
            declarations = inputs.overlays.declarations,
            host = inputs.overlays.host,
            runtime = inputs.overlays.runtime,
        })
    end,
    function(_, _, inputs)
        return inputs.mutation.sync()
    end,
    function(ownerId, _, inputs)
        return hotkeys.install(ownerId, inputs.hotkeys)
    end,
    function(ownerId, owner, inputs)
        if not inputs.fallbackUiRequested then
            return nil
        end
        return fallbackUi.install(ownerId, owner)
    end,
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
    overlays = overlays,
    mutation = mutation,
    draw = draw,
    controlRefs = controlsBundle.refs,
    hotkeys = hotkeys,
})

public.modpack = import('core/modpack/init.lua', nil, {
    rom = externals.rom,
    createTheme = createTheme,
    uiSession = uiSession,
    setupRunData = gameDeps.runData.SetupRunData,
    storage = storage,
    coordination = modpackCoordination,
    overlaySurface = overlaysBundle.modpack,
    getLiveModule = moduleRegistry.getLiveModule,
    packRegistry = registry.modpacks,
    hotkeys = hotkeys,
    createModuleFrame = createModuleFrame,
    hotkeyOverview = hotkeyOverview,
    openLibWindow = libWindow.openHotkeys,
})
local moduleBundle = import('core/module_bootstrap/module.lua', nil, {
    logging = logging,
    identifiers = identifiers,
    managedModule = managedModule,
    definition = definition,
    moduleRegistry = moduleRegistry,
    moduleActivation = moduleActivation,
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
    hotkeyDeclarations = hotkeyDeclarations,
})
public.createModule = moduleBundle.public.createModule

return {
    libWindow = libWindow,
}
