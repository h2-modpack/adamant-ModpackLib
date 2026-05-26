local deps = ...

local runtimeRoot = deps.runtimeRoot

-- Centralized hot-reload-stable Lib root buckets. Adding a new persistent
-- subsystem bucket should be a conscious change in this file.
runtimeRoot.registry = runtimeRoot.registry or {}

local buckets = runtimeRoot.registry
buckets.hosts = buckets.hosts or {}
buckets.hooks = buckets.hooks or {}
buckets.shared = buckets.shared or {}
buckets.shared.events = buckets.shared.events or {}
buckets.shared.data = buckets.shared.data or {}
buckets.mutations = buckets.mutations or {}
buckets.overlays = buckets.overlays or {}
buckets.fallback = buckets.fallback or {}
buckets.coordinators = buckets.coordinators or {}
buckets.cache = buckets.cache or {}

return {
    hosts = buckets.hosts,
    hooks = buckets.hooks,
    shared = buckets.shared,
    mutations = buckets.mutations,
    overlays = buckets.overlays,
    fallback = buckets.fallback,
    coordinators = buckets.coordinators,
    cache = buckets.cache,
}
