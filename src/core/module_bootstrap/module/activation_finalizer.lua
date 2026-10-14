local deps = ...

local logging = deps.logging
local managedModule = deps.managedModule
local moduleActivation = deps.moduleActivation
local definitionApi = deps.definition
local moduleRegistry = deps.moduleRegistry
local moduleState = deps.moduleState
local fallbackUi = deps.fallbackUi
local controlCompiler = deps.controlCompiler
local statusDeclarations = deps.statusDeclarations
local hotkeyDeclarations = deps.hotkeyDeclarations

local activationFinalizer = {}

local function getStructuralBaseline(pluginGuid)
    local previousModule = moduleRegistry.getLiveModule(pluginGuid)
    local previousRecord = moduleRegistry.getRecord(previousModule)
    local previousDefinition = previousRecord and previousRecord.definition or nil
    local previousFingerprint = previousDefinition and previousDefinition._structuralFingerprint or nil
    if previousFingerprint == nil then
        return nil
    end
    return {
        _definitionStructuralFingerprint = previousFingerprint,
    }
end

local function attachFallbackUi(declarations, pluginGuid)
    for _, register in ipairs(declarations.fallbackUi) do
        fallbackUi.attachGuiOnce(pluginGuid, register)
    end
end

local function appendList(target, source)
    for _, value in ipairs(source or {}) do
        target[#target + 1] = value
    end
end

local function mergePublicStorage(storage, statusStorage, hotkeyStorage)
    local merged = {}
    appendList(merged, storage)
    appendList(merged, statusStorage)
    appendList(merged, hotkeyStorage)
    if #merged == 0 then
        return nil
    end
    return merged
end

local function createDefinitionInput(opts, declarations, statusStorage, hotkeyStorage)
    return {
        modpack = opts.modpack,
        id = opts.id,
        name = opts.name,
        shortName = opts.shortName,
        tooltip = opts.tooltip,
        hash = opts.hash,
        storage = mergePublicStorage(declarations.storage, statusStorage, hotkeyStorage),
        cache = declarations.cache,
        actions = declarations.actions,
    }
end

local function mergeMaps(target, source)
    for key, value in pairs(source or {}) do
        target[key] = value
    end
end

---Seals the facade's declarations into a prepared definition, module state, and an activated
---managed module instance.
---@return AdamantModpackLib.ManagedModule module
---@return { host: AdamantModpackLib.Host, runtime: AdamantModpackLib.RuntimeContext } contexts
function activationFinalizer.activate(opts, declarations)
    if type(declarations.drawTab) ~= "function" then
        logging.violate("module.invalid_create_opts", "module.ui.tab must be declared before module.activate")
    end

    local compiledControls = controlCompiler.compile(declarations.controlDeclarations)
    local statusStorage = statusDeclarations.compileStorage(declarations.status)
    -- Hotkey bindings are public data roots (authors may keep an existing alias), so they merge
    -- with the module's own storage rather than Lib-internal storage.
    local compiledHotkeys = hotkeyDeclarations.compile(declarations.hotkeys, declarations.storage, statusStorage)
    local internalStorage = {}
    local internalActions = {}
    appendList(internalStorage, declarations.internalStorage)
    appendList(internalStorage, compiledControls.storage)
    mergeMaps(internalActions, declarations.internalActions)

    local definition = definitionApi.prepareDefinitionWithInternalDeclarations(getStructuralBaseline(opts.pluginGuid),
        createDefinitionInput(opts, declarations, statusStorage, compiledHotkeys.storage), {
            hasQuickContent = type(declarations.drawQuickContent) == "function",
        }, {
            storage = internalStorage,
            actions = internalActions,
        })
    local state = moduleState.create(definition, {
        pluginGuid = opts.pluginGuid,
    })
    local module, contexts = managedModule.create({
        definition = definition,
        pluginGuid = opts.pluginGuid,
        state = state,
        mutationBundle = declarations.mutationBundle,
        hookDeclarations = declarations.hookDeclarations,
        sharedDataDeclarations = declarations.sharedDataDeclarations,
        sharedEventRegistrations = declarations.sharedEventRegistrations,
        overlayDeclarations = declarations.overlayDeclarations,
        fallbackUiRequested = #declarations.fallbackUi > 0,
        onActivate = declarations.onActivate,
        onCommit = declarations.onCommit,
        onReload = declarations.onReload,
        drawTab = declarations.drawTab,
        drawQuickContent = declarations.drawQuickContent,
        controlCatalog = compiledControls.catalog,
        hotkeyRequests = compiledHotkeys.requests,
    })
    attachFallbackUi(declarations, opts.pluginGuid)
    -- Raises on failure; the facade's `module.activate()` owns the single activate_failed report.
    moduleActivation.activateOrThrow(module)
    return module, contexts
end

return activationFinalizer
