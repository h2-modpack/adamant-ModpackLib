local deps = ...

local logging = deps.logging
local moduleHost = deps.moduleHost
local moduleState = deps.moduleState
local modulePublic = {}

---@class ModuleCreateOpts
---@field pluginGuid string
---@field config table
---@field modpack string|nil
---@field id string
---@field name string
---@field shortName string|nil
---@field tooltip string|nil
---@field storage StorageSchema|nil
---@field hashGroupPlan HashGroupPlan|nil
---@field onSettingsCommitted fun(host: AuthorHost, store: AuthorStore, commit: table)|nil
---@field drawTab fun(draw: DrawContext, data: AuthorSession, actions: DrawActions, services: DrawServices)
---@field drawQuickContent fun(draw: DrawContext, data: AuthorSession, actions: DrawActions, services: DrawServices)|nil

local KnownModuleOpts = {
    pluginGuid = true,
    config = true,
    modpack = true,
    id = true,
    name = true,
    shortName = true,
    tooltip = true,
    storage = true,
    hashGroupPlan = true,
    onSettingsCommitted = true,
    drawTab = true,
    drawQuickContent = true,
}

local function ValidateKnownOpts(opts)
    for key in pairs(opts) do
        if key == "definition" then
            logging.violate(
                "host.unknown_opt",
                "createModule: definition table is no longer supported; put definition fields at top level"
            )
        end
        if not KnownModuleOpts[key] then
            logging.violate("host.unknown_opt", "createModule: unknown option '%s'", tostring(key))
        end
    end
end

local function BuildDefinitionInput(opts)
    return {
        modpack = opts.modpack,
        id = opts.id,
        name = opts.name,
        shortName = opts.shortName,
        tooltip = opts.tooltip,
        storage = opts.storage,
        hashGroupPlan = opts.hashGroupPlan,
    }
end

local function GetStructuralBaseline(pluginGuid)
    local previousHost = moduleHost.getLiveHost(pluginGuid)
    local previousState = moduleHost.getState(previousHost)
    local previousDefinition = previousState and previousState.definition or nil
    local previousFingerprint = previousDefinition and previousDefinition._structuralFingerprint or nil
    if previousFingerprint == nil then
        return nil
    end
    return {
        _definitionStructuralFingerprint = previousFingerprint,
    }
end

--- Creates a module through the canonical prepare -> store -> host pipeline.
--- Throws on construction failure. Public module construction uses the safe
--- wrapper below so module load can skip cleanly on invalid definitions.
local function createModuleOrThrow(opts)
    if type(opts) ~= "table" then
        logging.violate("host.invalid_create_opts", "createModule: opts must be a table")
    end
    ValidateKnownOpts(opts)
    if type(opts.config) ~= "table" then
        logging.violate("host.invalid_create_opts", "createModule: config is required")
    end
    if type(opts.pluginGuid) ~= "string" or opts.pluginGuid == "" then
        logging.violate("host.invalid_create_opts", "createModule: pluginGuid is required")
    end

    local definition = moduleHost.prepareDefinition(GetStructuralBaseline(opts.pluginGuid), BuildDefinitionInput(opts), {
        hasQuickContent = type(opts.drawQuickContent) == "function",
    })
    local state = moduleState.create(opts.config, definition)
    local store = state.store
    local session = state.session
    local cacheStore = state.cacheStore
    local _, authorHost, authorStore = moduleHost.create({
        definition = definition,
        pluginGuid = opts.pluginGuid,
        store = store,
        session = session,
        cacheStore = cacheStore,
        onSettingsCommitted = opts.onSettingsCommitted,
        drawTab = opts.drawTab,
        drawQuickContent = opts.drawQuickContent,
    })
    return authorHost, authorStore
end

--- Safely creates a module through the canonical prepare -> store -> host pipeline.
--- Returns nils plus the construction error instead of throwing.
---@param opts ModuleCreateOpts
---@return AuthorHost|nil host
---@return AuthorStore|nil store
---@return string|nil err
local function createModule(opts)
    local ok, host, store = pcall(createModuleOrThrow, opts)
    if ok then
        return host, store, nil
    end

    local err = tostring(host)
    logging.violate("host.create_failed", "createModule failed; skipping module: %s", err)
    return nil, nil, err
end
modulePublic.createModule = createModule

return {
    public = modulePublic,
    createModuleOrThrow = createModuleOrThrow,
}
