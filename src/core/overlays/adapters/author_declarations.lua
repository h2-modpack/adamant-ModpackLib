local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local declarations = deps.declarations
local overlayOrder = deps.order
local author = {}

local function requireHostRecord(host, apiName)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("overlays.invalid_registration", "%s: expected managed module host", apiName)
    end
    return record
end

local function requireDeclarationOpen(host, apiName)
    local record = requireHostRecord(host, "host.overlays." .. apiName)
    if record.activating == true then
        logging.violate("overlays.invalid_registration", "host.overlays.%s cannot be called during host activation", apiName)
    end
    if record.activated == true then
        logging.violate("overlays.invalid_registration", "host.overlays.%s cannot be called after host activation", apiName)
    end
    return record
end

local function ensureHostDeclarations(record)
    if not record.overlayDeclarations then
        record.overlayDeclarations = declarations.create()
    end
    return record.overlayDeclarations
end

function author.create(host)
    return {
        order = overlayOrder,
        createLine = function(name, spec)
            local record = requireDeclarationOpen(host, "createLine")
            return declarations.declareLine(ensureHostDeclarations(record), "host.overlays.createLine", name, spec)
        end,
        createTable = function(name, spec)
            local record = requireDeclarationOpen(host, "createTable")
            return declarations.declareTable(ensureHostDeclarations(record), "host.overlays.createTable", name, spec)
        end,
        onCommit = function(callback)
            local record = requireDeclarationOpen(host, "onCommit")
            return declarations.declareCommit(ensureHostDeclarations(record), "host.overlays.onCommit", callback)
        end,
        onInterval = function(name, seconds, callback, opts)
            local record = requireDeclarationOpen(host, "onInterval")
            return declarations.declareInterval(
                ensureHostDeclarations(record),
                "host.overlays.onInterval",
                name,
                seconds,
                callback,
                opts
            )
        end,
        afterHook = function(path, callback)
            local record = requireDeclarationOpen(host, "afterHook")
            return declarations.declareAfterHook(ensureHostDeclarations(record), "host.overlays.afterHook", path, callback)
        end,
    }
end

return author
