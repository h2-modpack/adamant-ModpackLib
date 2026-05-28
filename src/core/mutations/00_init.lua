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

local service = import('core/mutations/adapters/module_lifecycle.lua', nil, {
    logging = deps.logging,
    moduleRegistry = deps.moduleRegistry,
    lifecycle = lifecycle,
})

return {
    service = service,
    lifecycle = lifecycle,
    plan = plan,
}
