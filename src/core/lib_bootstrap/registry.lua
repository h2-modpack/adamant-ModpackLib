local deps = ...

local runtimeRoot = deps.runtimeRoot

-- Centralized hot-reload-stable Lib root buckets. Adding a new persistent
-- subsystem bucket should be a conscious change in this file.
runtimeRoot.registry = runtimeRoot.registry or {}

local buckets = runtimeRoot.registry
buckets.hosts = buckets.hosts or {}
buckets.hooks = buckets.hooks or {}
buckets.integrations = buckets.integrations or {}
buckets.mutations = buckets.mutations or {}
buckets.overlays = buckets.overlays or {}
buckets.fallback = buckets.fallback or {}
buckets.coordinators = buckets.coordinators or {}

return {
    hosts = buckets.hosts,
    hooks = buckets.hooks,
    integrations = buckets.integrations,
    mutations = buckets.mutations,
    overlays = buckets.overlays,
    fallback = buckets.fallback,
    coordinators = buckets.coordinators,
}
