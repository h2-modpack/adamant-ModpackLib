local deps = ...

local logging = deps.logging
local hostState = deps.hostState
local lifecycle = deps.lifecycle

local hostAdapter = {
    affectsRunData = lifecycle.affectsRunData,
}

local function requireHostState(host, apiName)
    local state = hostState.get(host)
    if not state then
        logging.violate("mutation.invalid_registration", "%s: expected managed module host state", apiName)
    end
    return state
end

local function getHostState(host, apiName)
    local state = requireHostState(host, apiName)
    return state
end

function hostAdapter.applyForHost(host)
    local state = getHostState(host, "mutation.applyForHost")
    return lifecycle.apply(host.getHostId(), state.mutationBundle, state.authorHost, state.authorStore)
end

function hostAdapter.syncForHost(host)
    local state = getHostState(host, "mutation.syncForHost")
    return lifecycle.sync(host.getHostId(), state.definition, state.mutationBundle, state.authorHost, state.authorStore)
end

function hostAdapter.revertForHost(host)
    getHostState(host, "mutation.revertForHost")
    return lifecycle.revert(host.getHostId())
end

return hostAdapter
