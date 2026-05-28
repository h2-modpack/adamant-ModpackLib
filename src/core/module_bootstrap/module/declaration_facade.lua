local deps = ...

local logging = deps.logging
local overlayOrder = deps.overlayOrder
local options = deps.options
local declarationSurface = deps.declarationSurface
local activationFinalizer = deps.activationFinalizer
local hookDeclarations = deps.hookDeclarations
local overlayDeclarations = deps.overlayDeclarations
local sharedDataDeclarations = deps.sharedDataDeclarations
local sharedRegistrations = deps.sharedRegistrations

local declarationFacade = {}

local function createDeclarationState()
    return {
        storage = nil,
        cache = nil,
        actions = nil,
        onCommit = nil,
        hashGroupPlan = nil,
        drawTab = nil,
        drawQuickContent = nil,
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

local function attachModuleUtilitySurface(module, opts, lifecycle)
    function module.isEnabled()
        local activeModule = lifecycle.getActiveModule()
        if activeModule then
            return activeModule.isEnabled()
        end
        return opts.config and opts.config.Enabled == true
    end

    function module.getHostId()
        return opts.pluginGuid
    end

    function module.getModuleId()
        return opts.id
    end

    function module.getPackId()
        return opts.modpack
    end

    function module.getMeta()
        return {
            name = opts.name,
            shortName = opts.shortName,
            tooltip = opts.tooltip,
        }
    end

    function module.log(fmt, ...)
        local activeModule = lifecycle.getActiveModule()
        if activeModule then
            return activeModule.log(fmt, ...)
        end
        logging.printWithPrefix("[" .. tostring(opts.id or opts.pluginGuid) .. "] ", fmt, ...)
    end

    function module.logIf(fmt, ...)
        local activeModule = lifecycle.getActiveModule()
        if activeModule then
            return activeModule.logIf(fmt, ...)
        end
        if opts.config and opts.config.DebugMode == true then
            logging.printWithPrefix("[" .. tostring(opts.id or opts.pluginGuid) .. "] ", fmt, ...)
        end
    end
end

function declarationFacade.create(opts)
    options.validateIdentity(opts)

    local activated = false
    local activating = false
    local activeModule = nil
    local activeRecord = nil
    local declarations = createDeclarationState()
    local module = {}

    local lifecycle = {}

    function lifecycle.requireOpen(context)
        if activated or activating then
            logging.violate("host.invalid_create_opts", "%s cannot be called after module activation begins", context)
        end
    end

    function lifecycle.requireActive(context)
        if not activeModule then
            logging.violate("host.not_activated", "%s requires module.activate() before it can run", context)
        end
        return activeModule
    end

    function lifecycle.getActiveModule()
        return activeModule
    end

    function lifecycle.getActiveRecord()
        return activeRecord
    end

    local function activateOrThrow()
        if activated then
            logging.violate("host.already_activated", "module.activate: module is already activated")
        end
        if activating then
            logging.violate("host.activation_in_progress", "module.activate: module activation is already in progress")
        end
        activating = true
        activeModule, activeRecord = activationFinalizer.activate(opts, declarations)
        activated = true
        activating = false
        return true, nil
    end

    function module.activate()
        local ok, err = pcall(activateOrThrow)
        if ok then
            return true, nil
        end
        activating = false
        err = tostring(err)
        logging.violate("host.activate_failed", "module.activate failed; skipping module: %s", err)
        return false, err
    end

    declarationSurface.attach(module, declarations, lifecycle, overlayOrder)
    attachModuleUtilitySurface(module, opts, lifecycle)

    return module, nil
end

return declarationFacade
