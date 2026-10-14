local deps = ...

local logging = deps.logging
local moduleIdentity = deps.moduleIdentity
local options = deps.options
local declarationSurface = deps.declarationSurface
local activationFinalizer = deps.activationFinalizer
local hookDeclarations = deps.hookDeclarations
local overlayDeclarations = deps.overlayDeclarations
local sharedDataDeclarations = deps.sharedDataDeclarations
local sharedRegistrations = deps.sharedRegistrations
local controlDeclarations = deps.controlDeclarations

local declarationFacade = {}

local function createDeclarationState()
    return {
        storage = nil,
        status = nil,
        internalStorage = nil,
        internalActions = nil,
        cache = nil,
        actions = nil,
        onActivate = nil,
        onCommit = nil,
        onReload = nil,
        drawTab = nil,
        drawQuickContent = nil,
        controlDeclarations = controlDeclarations.create(),
        fallbackUi = {},
        hookDeclarations = hookDeclarations.create(),
        sharedDataDeclarations = sharedDataDeclarations.createDeclarations(),
        sharedEventRegistrations = sharedRegistrations.create(),
        mutationBundle = {
            patchMutation = nil,
        },
        overlayDeclarations = overlayDeclarations.create(),
    }
end

-- The facade is the builder; the managed instance built at activation owns runtime behavior.
-- Identity comes from the same constructor as the instance's (`identity.lua`); the prepared
-- definition copies these opts verbatim, so both report the same values.
local function attachModuleUtilitySurface(module, opts, getActiveModule)
    local identity = moduleIdentity.create(opts, opts.pluginGuid, function()
        local activeModule = getActiveModule()
        return activeModule ~= nil and activeModule.read("DebugMode") == true
    end)
    module.getOwnerId = identity.getOwnerId
    module.getModuleId = identity.getModuleId
    module.getPackId = identity.getPackId
    module.getMeta = identity.getMeta
    module.log = identity.log
    module.logIf = identity.logIf

    function module.isEnabled()
        local activeModule = getActiveModule()
        return activeModule ~= nil and activeModule.isEnabled()
    end
end

function declarationFacade.create(opts)
    options.validateIdentity(opts)

    -- Activation state: the managed instance's record owns activation proper. The facade only
    -- tracks `sealing` (finalizer running, no instance yet) and the instance it produced.
    local sealing = false
    local activeModule = nil
    local activeContexts = nil
    local declarations = createDeclarationState()
    local module = {}

    local lifecycle = {}

    function lifecycle.requireOpen(context)
        if activeModule ~= nil or sealing then
            logging.violate("module.invalid_create_opts", "%s cannot be called after module activation begins", context)
        end
    end

    ---@return { host: AdamantModpackLib.Host, runtime: AdamantModpackLib.RuntimeContext }?
    function lifecycle.getActiveContexts()
        return activeContexts
    end

    local function activateOrThrow()
        if activeModule ~= nil then
            logging.violate("managed_module.already_activated", "module.activate: module is already activated")
        end
        if sealing then
            logging.violate("managed_module.activation_in_progress", "module.activate: module activation is already in progress")
        end
        sealing = true
        activeModule, activeContexts = activationFinalizer.activate(opts, declarations)
        sealing = false
        return true, nil
    end

    function module.activate()
        local ok, err = pcall(activateOrThrow)
        if ok then
            return true, nil
        end
        sealing = false
        err = tostring(err)
        logging.violate("managed_module.activate_failed", "module.activate failed; skipping module: %s", err)
        return false, err
    end

    declarationSurface.attach(module, declarations, lifecycle)
    attachModuleUtilitySurface(module, opts, function()
        return activeModule
    end)

    return module, nil
end

return declarationFacade
