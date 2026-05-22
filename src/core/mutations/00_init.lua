local deps = ...

local mutationRegistry = deps.mutationRegistry
-- Hot-reload-stable mutation records. Active plans must remain revertible
-- across Lib re-imports because they may already be applied to run data.
mutationRegistry.ownerSlots = mutationRegistry.ownerSlots or {}
mutationRegistry.planExecutors = mutationRegistry.planExecutors or setmetatable({}, { __mode = "k" })

local plan = import('core/mutations/plan.lua', nil, {
    values = deps.values,
    planExecutors = mutationRegistry.planExecutors,
})

local lifecycle = import('core/mutations/lifecycle.lua', nil, {
    logging = deps.logging,
    coordinator = deps.coordinator,
    setupRunData = deps.gameDeps.runData.SetupRunData,
    mutationRegistry = mutationRegistry,
    plan = plan,
})

local service = import('core/mutations/adapters/host_lifecycle.lua', nil, {
    logging = deps.logging,
    hostRegistry = deps.hostRegistry,
    lifecycle = lifecycle,
})

local author = import('core/mutations/adapters/author_patch.lua', nil, {
    logging = deps.logging,
    hostRegistry = deps.hostRegistry,
    lifecycle = lifecycle,
})

return {
    service = service,
    author = author,
    plan = plan,
}
