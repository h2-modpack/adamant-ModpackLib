local deps = ...

local logging = deps.logging
local modulePublic = {}
local options = import('core/module_bootstrap/module/options.lua', nil, {
    logging = logging,
})
local declarationSurface = import('core/module_bootstrap/module/declaration_surface.lua', nil, {
    logging = logging,
    hookDeclarations = deps.hookDeclarations,
    overlayDeclarations = deps.overlayDeclarations,
    sharedDataDeclarations = deps.sharedDataDeclarations,
    sharedRegistrations = deps.sharedRegistrations,
    mutationLifecycle = deps.mutationLifecycle,
    controlDeclarations = deps.controlDeclarations,
})
local activationFinalizer = import('core/module_bootstrap/module/activation_finalizer.lua', nil, {
    logging = logging,
    managedModule = deps.managedModule,
    moduleState = deps.moduleState,
    fallbackUi = deps.fallbackUi,
    controlCompiler = deps.controlCompiler,
})
local declarationFacade = import('core/module_bootstrap/module/declaration_facade.lua', nil, {
    logging = logging,
    overlayOrder = deps.overlayOrder,
    options = options,
    declarationSurface = declarationSurface,
    activationFinalizer = activationFinalizer,
    hookDeclarations = deps.hookDeclarations,
    overlayDeclarations = deps.overlayDeclarations,
    sharedDataDeclarations = deps.sharedDataDeclarations,
    sharedRegistrations = deps.sharedRegistrations,
    controlDeclarations = deps.controlDeclarations,
})

--- Creates a module declaration facade.
--- Throws on construction failure. Public module construction uses the safe
--- wrapper below so module load can skip cleanly on invalid identities.
local function createModuleOrThrow(opts)
    if type(opts) ~= "table" then
        logging.violate("host.invalid_create_opts", "createModule: opts must be a table")
    end
    options.validateKnown(opts)
    return declarationFacade.create(opts)
end

--- Safely creates a module declaration facade.
--- Returns nil plus the construction error instead of throwing.
---@param opts ModuleCreateOpts
---@return AuthorModule|nil module
---@return string|nil err
local function createModule(opts)
    local ok, module = pcall(createModuleOrThrow, opts)
    if ok then
        return module, nil
    end

    local err = tostring(module)
    logging.violate("host.create_failed", "createModule failed; skipping module: %s", err)
    return nil, err
end
modulePublic.createModule = createModule

return {
    public = modulePublic,
    createModuleOrThrow = createModuleOrThrow,
}
