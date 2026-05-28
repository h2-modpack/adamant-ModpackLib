local deps = ...

local logging = deps.logging
local managedModule = deps.managedModule
local moduleState = deps.moduleState
local fallbackUi = deps.fallbackUi

local activationFinalizer = {}

local function getStructuralBaseline(pluginGuid)
    local previousModule = managedModule.getLiveHost(pluginGuid)
    local previousRecord = managedModule.getRecord(previousModule)
    local previousDefinition = previousRecord and previousRecord.definition or nil
    local previousFingerprint = previousDefinition and previousDefinition._structuralFingerprint or nil
    if previousFingerprint == nil then
        return nil
    end
    return {
        _definitionStructuralFingerprint = previousFingerprint,
    }
end

local function createDefinitionInput(opts, declarations)
    return {
        modpack = opts.modpack,
        id = opts.id,
        name = opts.name,
        shortName = opts.shortName,
        tooltip = opts.tooltip,
        storage = declarations.storage,
        cache = declarations.cache,
        actions = declarations.actions,
        hashGroupPlan = declarations.hashGroupPlan,
    }
end

local function attachFallbackUi(declarations, module)
    for _, args in ipairs(declarations.fallbackUi) do
        fallbackUi.attachGuiOnce(module, table.unpack(args, 1, args.n))
    end
end

function activationFinalizer.activate(opts, declarations)
    if type(declarations.drawTab) ~= "function" then
        logging.violate("host.invalid_create_opts", "module.ui.tab must be declared before module.activate")
    end

    local definition = managedModule.prepareDefinition(getStructuralBaseline(opts.pluginGuid),
        createDefinitionInput(opts, declarations), {
            hasQuickContent = type(declarations.drawQuickContent) == "function",
        })
    local state = moduleState.create(opts.config, definition)
    local module = managedModule.create({
        definition = definition,
        pluginGuid = opts.pluginGuid,
        persistentState = state.persistentState,
        stagedState = state.stagedState,
        mutationBundle = declarations.mutationBundle,
        hookDeclarations = declarations.hookDeclarations,
        sharedDataDeclarations = declarations.sharedDataDeclarations,
        sharedEventRegistrations = declarations.sharedEventRegistrations,
        overlayDeclarations = declarations.overlayDeclarations,
        onCommit = declarations.onCommit,
        drawTab = declarations.drawTab,
        drawQuickContent = declarations.drawQuickContent,
    })
    attachFallbackUi(declarations, module)
    local ok, err = module.activate()
    if not ok then
        error(err, 0)
    end
    return module, managedModule.getRecord(module)
end

return activationFinalizer
