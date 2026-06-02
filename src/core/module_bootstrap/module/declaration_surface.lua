local deps = ...

local logging = deps.logging
local hookDeclarations = deps.hookDeclarations
local overlayDeclarations = deps.overlayDeclarations
local sharedDataDeclarations = deps.sharedDataDeclarations
local sharedRegistrations = deps.sharedRegistrations
local mutationLifecycle = deps.mutationLifecycle
local controlDeclarations = deps.controlDeclarations

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

local function requireActiveRecord(lifecycle, context)
    local record = lifecycle.getActiveRecord()
    if not record then
        logging.violate("managed_module.not_activated", "%s requires module.activate() before it can run", context)
    end
    return record
end

function declarationSurface.attach(module, declarations, lifecycle, overlayOrder)
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
            setOnce("storage", storage, "module.data.define")
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

    module.ui = {
        tab = function(callback)
            setFunctionOnce("drawTab", callback, "module.ui.tab")
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

    module.fallbackUi = {
        attachGuiOnce = function(register)
            lifecycle.requireOpen("module.fallbackUi.attachGuiOnce")
            declarations.fallbackUi[#declarations.fallbackUi + 1] = copyArgs(register)
        end,
    }

    module.hooks = {
        wrap = function(path, keyOrHandler, maybeHandler)
            lifecycle.requireOpen("module.hooks.wrap")
            local keyOrAdaptedHandler, adaptedHandler = adaptHookCallback(keyOrHandler, maybeHandler,
                function(handler)
                    return function(base, ...)
                        local record = requireActiveRecord(lifecycle, "module.hooks.wrap callback")
                        return handler(record.host, record.runtime, base, ...)
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
                        local record = requireActiveRecord(lifecycle, "module.hooks.override callback")
                        return replacement(record.host, record.runtime, ...)
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
                        local record = requireActiveRecord(lifecycle, "module.hooks.contextWrap callback")
                        return context(record.host, record.runtime, ...)
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
                        local record = lifecycle.getActiveRecord()
                        return record and record.host or nil
                    end,
                    ...)
            end,
            reader = function(...)
                lifecycle.requireOpen("module.shared.data.reader")
                return sharedDataDeclarations.stageReaderDeclaration(
                    declarations.sharedDataDeclarations,
                    function()
                        local record = lifecycle.getActiveRecord()
                        return record and record.host or nil
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
                local record = requireActiveRecord(lifecycle, "module.shared.listen callback")
                return callback(record.host, record.runtime, payload)
            end
            return sharedRegistrations.stageListener(
                declarations.sharedEventRegistrations,
                function()
                    local record = lifecycle.getActiveRecord()
                    return record and record.host or nil
                end,
                id,
                eventName,
                wrappedCallback)
        end,
        emit = function(...)
            local record = requireActiveRecord(lifecycle, "module.shared.emit")
            return record.host.shared.emit(...)
        end,
    }

    module.mutation = {
        patch = function(callback)
            lifecycle.requireOpen("module.mutation.patch")
            return mutationLifecycle.declarePatch(declarations.mutationBundle, callback)
        end,
    }

    module.overlays = {
        order = overlayOrder,
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
