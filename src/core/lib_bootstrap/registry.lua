local deps = ...

local runtimeRoot = deps.runtimeRoot

-- Centralized hot-reload-stable Lib root buckets. Adding a new persistent
-- subsystem bucket should be a conscious change in this file.
runtimeRoot.registry = runtimeRoot.registry or {}

local buckets = runtimeRoot.registry
buckets.modules = buckets.modules or {}
buckets.hooks = buckets.hooks or {}
buckets.shared = buckets.shared or {}
buckets.mutations = buckets.mutations or {}
buckets.overlays = buckets.overlays or {}
buckets.fallback = buckets.fallback or {}
buckets.coordinators = buckets.coordinators or {}
buckets.modpacks = buckets.modpacks or {}
buckets.hotkeys = buckets.hotkeys or {}
buckets.ui = buckets.ui or {}

return {
    modules = buckets.modules,
    hooks = buckets.hooks,
    shared = buckets.shared,
    mutations = buckets.mutations,
    overlays = buckets.overlays,
    fallback = buckets.fallback,
    coordinators = buckets.coordinators,
    modpacks = buckets.modpacks,
    hotkeys = buckets.hotkeys,
    ui = buckets.ui,
}
