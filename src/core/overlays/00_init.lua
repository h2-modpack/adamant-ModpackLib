local deps = ...

-- Shared overlay order bands used by module and system retained overlays.
local overlayOrder = {
    system = 0,
    modpack = 100,
    module = 1000,
    debug = 2000,
}

local overlayRegistry = import('core/overlays/registry.lua', nil, {
    overlayRegistry = deps.overlayRegistry,
})

local suppression = import('core/overlays/suppression.lua', nil, {
    state = overlayRegistry,
})

local layout = import('core/overlays/layout.lua', nil, {
    gameDeps = deps.gameDeps.overlays,
    order = overlayOrder,
    values = deps.values,
})

local hudComponents = import('core/overlays/hud_components.lua', nil, {
    gameDeps = deps.gameDeps.overlays,
    values = deps.values,
    groupDestinations = layout.GROUP_DESTINATIONS,
})

local renderer = import('core/overlays/renderer.lua', nil, {
    gameDeps = deps.gameDeps.overlays,
    state = overlayRegistry.renderer,
    isUiSuppressed = suppression.isUiSuppressed,
    values = deps.values,
    order = overlayOrder,
    system = deps.rendererSystem,
    layout = layout,
    hudComponents = hudComponents,
    victoryStamp = import('core/overlays/victory_stamp.lua', nil, {
        gameDeps = deps.gameDeps.overlays,
        values = deps.values,
        hudComponents = hudComponents,
        stampLayout = layout.VICTORY_STAMP_LAYOUT,
        state = overlayRegistry.renderer,
    }),
})
local suppressForUi = suppression.bindSuppressForUi(renderer.refreshAll)

local declarations = import('core/overlays/declarations.lua', nil, {
    logging = deps.logging,
    regions = layout.REGIONS,
    fonts = hudComponents.FONTS,
})

local retained = import('core/overlays/retained.lua', nil, {
    state = overlayRegistry.retained,
    renderer = renderer,
    declarations = declarations,
    order = overlayOrder,
    rom = deps.rom,
})

local ownerInstall = import('core/overlays/owner_install.lua', nil, {
    hooks = deps.hooks,
    hookDeclarations = deps.hookDeclarations,
    retained = retained,
    declarations = declarations,
    receipt = deps.receipt,
})

local system = import('core/overlays/adapters/system_retained.lua', nil, {
    logging = deps.logging,
    retained = retained,
    order = overlayOrder,
})

return {
    service = {
        install = ownerInstall.install,
        suppressForUi = suppressForUi,
        -- Internal API: dispatch overlay projections after settings commit.
        dispatchCommit = retained.dispatchCommit,
    },
    system = system,
    modpack = import('core/overlays/adapters/modpack_overlays.lua', nil, {
        logging = deps.logging,
        suppressForUi = suppressForUi,
        system = system,
        order = overlayOrder,
    }),
    authoring = {
        declarations = declarations,
        order = overlayOrder,
        regions = declarations.regions,
        fonts = declarations.fonts,
    },
}
