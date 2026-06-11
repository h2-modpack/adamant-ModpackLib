local deps = ...

local logging = deps.logging
local managedModule = deps.managedModule
local moduleState = deps.moduleState
local fallbackUi = deps.fallbackUi
local controlCompiler = deps.controlCompiler
local statusDeclarations = deps.statusDeclarations

local activationFinalizer = {}

local function getStructuralBaseline(pluginGuid)
    local previousModule = managedModule.getLiveModule(pluginGuid)
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

local function attachFallbackUi(declarations, module)
    for _, args in ipairs(declarations.fallbackUi) do
        fallbackUi.attachGuiOnce(module, table.unpack(args, 1, args.n))
    end
end

local function appendList(target, source)
    for _, value in ipairs(source or {}) do
        target[#target + 1] = value
    end
end

local function mergePublicStorage(storage, statusStorage)
    local merged = {}
    appendList(merged, storage)
    appendList(merged, statusStorage)
    if #merged == 0 then
        return nil
    end
    return merged
end

local function createDefinitionInput(opts, declarations, statusStorage)
    return {
        modpack = opts.modpack,
        id = opts.id,
        name = opts.name,
        shortName = opts.shortName,
        tooltip = opts.tooltip,
        storage = mergePublicStorage(declarations.storage, statusStorage),
        cache = declarations.cache,
        actions = declarations.actions,
    }
end

local function mergeMaps(target, source)
    for key, value in pairs(source or {}) do
        target[key] = value
    end
end

function activationFinalizer.activate(opts, declarations)
    if type(declarations.drawTab) ~= "function" then
        logging.violate("module.invalid_create_opts", "module.ui.tab must be declared before module.activate")
    end

    local compiledControls = controlCompiler.compile(declarations.controlDeclarations)
    local statusStorage = statusDeclarations.compileStorage(declarations.status)
    local internalStorage = {}
    local internalActions = {}
    appendList(internalStorage, declarations.internalStorage)
    appendList(internalStorage, compiledControls.storage)
    mergeMaps(internalActions, declarations.internalActions)

    local definition = managedModule.prepareDefinitionWithInternalDeclarations(getStructuralBaseline(opts.pluginGuid),
        createDefinitionInput(opts, declarations, statusStorage), {
            hasQuickContent = type(declarations.drawQuickContent) == "function",
        }, {
            storage = internalStorage,
            actions = internalActions,
        })
    local state = moduleState.create(definition, {
        pluginGuid = opts.pluginGuid,
    })
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
        onActivate = declarations.onActivate,
        onCommit = declarations.onCommit,
        drawTab = declarations.drawTab,
        drawQuickContent = declarations.drawQuickContent,
        controlCatalog = compiledControls.catalog,
    })
    attachFallbackUi(declarations, module)
    local ok, err = module.activate()
    if not ok then
        error(err, 0)
    end
    return module, managedModule.getRecord(module)
end

return activationFinalizer
