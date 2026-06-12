local deps = ...

local service = {}

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

-- Shared overlay visibility gate. UI suppression is global because foreground
-- configuration UI and gameplay overlays should not compete for screen space.
local function isUiSuppressed()
    return next(overlayRegistry.uiSuppressors) ~= nil
end

local renderer = import('core/overlays/renderer.lua', nil, {
    gameDeps = deps.gameDeps.overlays,
    state = overlayRegistry.renderer,
    isUiSuppressed = isUiSuppressed,
    logging = deps.logging,
    values = deps.values,
    order = overlayOrder,
    system = deps.rendererSystem,
})

local retained = import('core/overlays/retained.lua', nil, {
    state = overlayRegistry.retained,
    renderer = renderer,
    logging = deps.logging,
    order = overlayOrder,
    rom = deps.rom,
    dispatchIntervals = function(now)
        return service.dispatchIntervals(now)
    end,
})

local declarations = import('core/overlays/declarations.lua', nil, {
    logging = deps.logging,
})

local moduleAdapter = import('core/overlays/adapters/module_install.lua', nil, {
    logging = deps.logging,
    moduleRegistry = deps.moduleRegistry,
    hooks = deps.hooks,
    retained = retained,
    declarations = declarations,
})

local system = import('core/overlays/adapters/system_retained.lua', nil, {
    logging = deps.logging,
    retained = retained,
    order = overlayOrder,
})

local suppression = import('core/overlays/suppression.lua', nil, {
    state = overlayRegistry,
    renderer = renderer,
    isUiSuppressed = isUiSuppressed,
})

service.installForModule = moduleAdapter.installForModule
service.suppressForUi = suppression.suppressForUi
service.isUiSuppressed = suppression.isUiSuppressed

local modpack = import('core/overlays/adapters/modpack_overlays.lua', nil, {
    logging = deps.logging,
    suppression = suppression,
    system = system,
    order = overlayOrder,
})

-- Internal API: dispatch overlay projections after settings commit.
function service.dispatchCommit(owner, commit)
    return retained.dispatchCommit(owner, commit)
end

-- Internal API: dispatch retained interval projections from the ImGui tick driver.
function service.dispatchIntervals(now)
    return retained.dispatchIntervals(now)
end

-- Internal API: dispatch an overlay after-hook projection registered by a retained owner.
function service.dispatchAfterHook(owner, path, args, results)
    return retained.dispatchAfterHook(owner, path, args, results)
end

return {
    service = service,
    declarations = declarations,
    system = system,
    modpack = modpack,
    order = overlayOrder,
}
