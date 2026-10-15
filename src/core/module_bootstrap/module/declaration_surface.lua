local deps = ...

local logging = deps.logging
local identifiers = deps.identifiers
local hookDeclarations = deps.hookDeclarations
local hookContext = deps.hookContext
local overlayAuthoring = deps.overlayAuthoring
local overlayDeclarations = overlayAuthoring.declarations
local sharedDataDeclarations = deps.sharedDataDeclarations
local sharedRegistrations = deps.sharedRegistrations
local mutationLifecycle = deps.mutationLifecycle
local controlDeclarations = deps.controlDeclarations
local hotkeyDeclarations = deps.hotkeyDeclarations
local unpackValues = table.unpack or _G.unpack

local declarationSurface = {}

local function copyArgs(...)
    return {
        n = select("#", ...),
        ...
    }
end

local function adaptHookCallback(keyOrCallback, maybeCallback, buildCallback)
    if maybeCallback == nil then
        if type(keyOrCallback) ~= "function" then
            return keyOrCallback, nil
        end
        return buildCallback(keyOrCallback), nil
    end
    if type(maybeCallback) ~= "function" then
        return keyOrCallback, maybeCallback
    end
    return keyOrCallback, buildCallback(maybeCallback)
end

local function requireActiveContexts(lifecycle, context)
    local active = lifecycle.getActiveContexts()
    if not active then
        logging.violate("managed_module.not_activated", "%s requires module.activate() before it can run", context)
    end
    return active
end

local function rejectPublicDataModeField(context, node)
    if type(node) ~= "table" or node.mode == nil then
        return
    end
    logging.violate(
        "storage.unknown_field",
        "%s: unknown storage field 'mode'",
        context
    )
end

local function validatePublicDataNode(context, node)
    rejectPublicDataModeField(context, node)

    if type(node) ~= "table" then
        return
    end

    for index, bit in ipairs(type(node.bits) == "table" and node.bits or {}) do
        rejectPublicDataModeField(context .. " bit #" .. tostring(index), bit)
    end

    for index, rowNode in ipairs(type(node.row) == "table" and node.row or {}) do
        validatePublicDataNode(context .. " row storage #" .. tostring(index), rowNode)
    end
end

local TAB_FIELDS = {
    id = true,
    label = true,
    draw = true,
    state = true,
}

---Validates `module.ui.tabs(...)` and returns a Lib-owned copy in declaration order.
---@param tabs any
---@return AdamantModpackLib.ModuleTabDeclaration[]
local function validateTabs(tabs)
    if type(tabs) ~= "table" or #tabs == 0 then
        logging.violate("module.invalid_create_opts", "module.ui.tabs requires a non-empty list of tabs")
    end
    local count = #tabs
    for key in pairs(tabs) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then
            logging.violate("module.invalid_create_opts", "module.ui.tabs: unexpected key '%s'; tabs must be a list",
                tostring(key))
        end
    end

    local copies = {}
    local seenIds = {}
    for index, tab in ipairs(tabs) do
        local context = "module.ui.tabs #" .. tostring(index)
        if type(tab) ~= "table" then
            logging.violate("module.invalid_create_opts", "%s must be a table", context)
        end
        for field in pairs(tab) do
            if not TAB_FIELDS[field] then
                logging.violate("module.invalid_create_opts", "%s: unknown field '%s'", context, tostring(field))
            end
        end
        if not identifiers.isStable(tab.id) then
            logging.violate("module.invalid_create_opts", "%s id '%s' %s", context, tostring(tab.id),
                identifiers.STABLE_DESCRIPTION)
        end
        if seenIds[tab.id] then
            logging.violate("module.invalid_create_opts", "%s: duplicate tab id '%s'", context, tab.id)
        end
        seenIds[tab.id] = true
        if type(tab.label) ~= "string" or tab.label == "" then
            logging.violate("module.invalid_create_opts", "%s label must be a non-empty string", context)
        end
        if type(tab.draw) ~= "function" then
            logging.violate("module.invalid_create_opts", "%s draw must be a function", context)
        end
        if tab.state ~= nil and type(tab.state) ~= "function" then
            logging.violate("module.invalid_create_opts", "%s state must be a function", context)
        end
        copies[index] = {
            id = tab.id,
            label = tab.label,
            draw = tab.draw,
            state = tab.state,
        }
    end
    return copies
end

local function validatePublicDataStorage(storage)
    if type(storage) ~= "table" then
        return
    end
    for index, node in ipairs(storage) do
        validatePublicDataNode("module.data.define storage #" .. tostring(index), node)
    end
end

function declarationSurface.attach(module, declarations, lifecycle)
    local function setOnce(field, value, context)
        lifecycle.requireOpen(context)
        if declarations[field] ~= nil then
            logging.violate("module.invalid_create_opts", "%s already declared", context)
        end
        declarations[field] = value
    end

    local function setFunctionOnce(field, value, context)
        if type(value) ~= "function" then
            logging.violate("module.invalid_create_opts", "%s callback must be a function", context)
        end
        setOnce(field, value, context)
    end

    module.data = {
        define = function(storage)
            validatePublicDataStorage(storage)
            setOnce("storage", storage, "module.data.define")
        end,
    }

    module.status = {
        define = function(status)
            setOnce("status", status, "module.status.define")
        end,
    }

    module.actions = {
        define = function(actions)
            setOnce("actions", actions, "module.actions.define")
        end,
    }

    module.cache = {
        define = function(cache)
            setOnce("cache", cache, "module.cache.define")
        end,
    }

    module.controls = {
        defineTemplates = function(templates)
            lifecycle.requireOpen("module.controls.defineTemplates")
            return controlDeclarations.defineTemplates(declarations.controlDeclarations, templates)
        end,
        define = function(instances)
            lifecycle.requireOpen("module.controls.define")
            return controlDeclarations.define(declarations.controlDeclarations, instances)
        end,
    }

    module.hotkeys = {
        request = function(id, opts)
            lifecycle.requireOpen("module.hotkeys.request")
            hotkeyDeclarations.request(declarations.hotkeys, id, opts)
        end,
    }

    -- `tab` and `tabs` are alternatives: one content tab, or several top-level tabs in the frame.
    module.ui = {
        tab = function(callback)
            lifecycle.requireOpen("module.ui.tab")
            if declarations.tabs ~= nil then
                logging.violate("module.invalid_create_opts", "module.ui.tab cannot be combined with module.ui.tabs")
            end
            setFunctionOnce("drawTab", callback, "module.ui.tab")
        end,
        tabs = function(tabs)
            lifecycle.requireOpen("module.ui.tabs")
            if declarations.drawTab ~= nil then
                logging.violate("module.invalid_create_opts", "module.ui.tabs cannot be combined with module.ui.tab")
            end
            if declarations.tabs ~= nil then
                logging.violate("module.invalid_create_opts", "module.ui.tabs already declared")
            end
            setOnce("tabs", validateTabs(tabs), "module.ui.tabs")
        end,
        header = function(callback)
            setFunctionOnce("drawHeader", callback, "module.ui.header")
        end,
        quickContent = function(callback)
            setFunctionOnce("drawQuickContent", callback, "module.ui.quickContent")
        end,
    }

    function module.onCommit(callback)
        setFunctionOnce("onCommit", callback, "module.onCommit")
    end

    function module.onActivate(callback)
        setFunctionOnce("onActivate", callback, "module.onActivate")
    end

    function module.onReload(callback)
        setFunctionOnce("onReload", callback, "module.onReload")
    end

    module.fallbackUi = {
        attachGuiOnce = function(register)
            lifecycle.requireOpen("module.fallbackUi.attachGuiOnce")
            if type(register) ~= "function" then
                logging.violate("fallback_ui.invalid_args", "module.fallbackUi.attachGuiOnce: register must be a function")
            end
            declarations.fallbackUi[#declarations.fallbackUi + 1] = register
        end,
    }

    module.hooks = {
        wrap = function(path, keyOrHandler, maybeHandler)
            lifecycle.requireOpen("module.hooks.wrap")
            local keyOrAdaptedHandler, adaptedHandler = adaptHookCallback(keyOrHandler, maybeHandler,
                function(handler)
                    return function(base, ...)
                        local active = requireActiveContexts(lifecycle, "module.hooks.wrap callback")
                        return handler(active.host, active.runtime, base, ...)
                    end
                end)
            return hookDeclarations.declareWrap(
                declarations.hookDeclarations,
                "module.hooks.wrap",
                path,
                keyOrAdaptedHandler,
                adaptedHandler
            )
        end,
        override = function(path, keyOrReplacement, maybeReplacement)
            lifecycle.requireOpen("module.hooks.override")
            local keyOrAdaptedReplacement, adaptedReplacement = adaptHookCallback(
                keyOrReplacement,
                maybeReplacement,
                function(replacement)
                    return function(...)
                        local active = requireActiveContexts(lifecycle, "module.hooks.override callback")
                        return replacement(active.host, active.runtime, ...)
                    end
                end)
            return hookDeclarations.declareOverride(
                declarations.hookDeclarations,
                "module.hooks.override",
                path,
                keyOrAdaptedReplacement,
                adaptedReplacement
            )
        end,
        contextWrap = function(path, keyOrContext, maybeContext)
            lifecycle.requireOpen("module.hooks.contextWrap")
            local keyOrAdaptedContext, adaptedContext = adaptHookCallback(keyOrContext, maybeContext,
                function(context)
                    return function(...)
                        local active = requireActiveContexts(lifecycle, "module.hooks.contextWrap callback")
                        local contextSurface, closeContextSurface = hookContext.createSurface()
                        local results = copyArgs(pcall(context, active.host, active.runtime, contextSurface, ...))
                        closeContextSurface()
                        if not results[1] then
                            error(results[2], 0)
                        end
                        return unpackValues(results, 2, results.n)
                    end
                end)
            return hookDeclarations.declareContextWrap(
                declarations.hookDeclarations,
                "module.hooks.contextWrap",
                path,
                keyOrAdaptedContext,
                adaptedContext
            )
        end,
    }

    module.shared = {
        data = {
            owner = function(...)
                lifecycle.requireOpen("module.shared.data.owner")
                return sharedDataDeclarations.stageOwnerDeclaration(
                    declarations.sharedDataDeclarations,
                    function()
                        local active = lifecycle.getActiveContexts()
                        return active and active.host or nil
                    end,
                    ...)
            end,
            reader = function(...)
                lifecycle.requireOpen("module.shared.data.reader")
                return sharedDataDeclarations.stageReaderDeclaration(
                    declarations.sharedDataDeclarations,
                    function()
                        local active = lifecycle.getActiveContexts()
                        return active and active.host or nil
                    end,
                    ...)
            end,
        },
        listen = function(id, eventName, callback)
            lifecycle.requireOpen("module.shared.listen")
            if type(callback) ~= "function" then
                logging.violate("module.invalid_create_opts", "module.shared.listen callback must be a function")
            end
            local function wrappedCallback(payload)
                local active = requireActiveContexts(lifecycle, "module.shared.listen callback")
                return callback(active.host, active.runtime, payload)
            end
            return sharedRegistrations.stageListener(
                declarations.sharedEventRegistrations,
                function()
                    local active = lifecycle.getActiveContexts()
                    return active and active.host or nil
                end,
                id,
                eventName,
                wrappedCallback)
        end,
    }

    module.mutation = {
        patch = function(callback)
            lifecycle.requireOpen("module.mutation.patch")
            return mutationLifecycle.declarePatch(declarations.mutationBundle, callback)
        end,
    }

    module.overlays = {
        order = overlayAuthoring.order,
        regions = overlayAuthoring.regions,
        fonts = overlayAuthoring.fonts,
        createLine = function(...)
            lifecycle.requireOpen("module.overlays.createLine")
            return overlayDeclarations.declareLine(declarations.overlayDeclarations, "module.overlays.createLine", ...)
        end,
        createTable = function(...)
            lifecycle.requireOpen("module.overlays.createTable")
            return overlayDeclarations.declareTable(declarations.overlayDeclarations, "module.overlays.createTable", ...)
        end,
        onCommit = function(...)
            lifecycle.requireOpen("module.overlays.onCommit")
            return overlayDeclarations.declareCommit(declarations.overlayDeclarations, "module.overlays.onCommit", ...)
        end,
        onInterval = function(...)
            lifecycle.requireOpen("module.overlays.onInterval")
            return overlayDeclarations.declareInterval(declarations.overlayDeclarations, "module.overlays.onInterval", ...)
        end,
        afterHook = function(...)
            lifecycle.requireOpen("module.overlays.afterHook")
            return overlayDeclarations.declareAfterHook(declarations.overlayDeclarations, "module.overlays.afterHook", ...)
        end,
    }
end

return declarationSurface
