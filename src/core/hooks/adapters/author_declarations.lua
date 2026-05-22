local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local declarations = deps.declarations
local author = {}

local function requireHostRecord(host, apiName)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("hooks.invalid_registration", "%s: expected managed module host", apiName)
    end
    return record
end

local function requireDeclarationOpen(host, apiName)
    local record = requireHostRecord(host, "host.hooks." .. apiName)
    if record.activating == true then
        logging.violate("hooks.invalid_registration", "host.hooks.%s cannot be called during host activation", apiName)
    end
    if record.activated == true then
        logging.violate("hooks.invalid_registration", "host.hooks.%s cannot be called after host activation", apiName)
    end
    return record
end

local function ensureHostDeclarations(record)
    if not record.hookDeclarations then
        record.hookDeclarations = declarations.create()
    end
    return record.hookDeclarations
end

function author.create(host)
    return {
        wrap = function(path, keyOrHandler, maybeHandler)
            local record = requireDeclarationOpen(host, "wrap")
            return declarations.declareWrap(
                ensureHostDeclarations(record),
                "host.hooks.wrap",
                path,
                keyOrHandler,
                maybeHandler
            )
        end,
        override = function(path, keyOrReplacement, maybeReplacement)
            local record = requireDeclarationOpen(host, "override")
            return declarations.declareOverride(
                ensureHostDeclarations(record),
                "host.hooks.override",
                path,
                keyOrReplacement,
                maybeReplacement
            )
        end,
        contextWrap = function(path, keyOrContext, maybeContext)
            local record = requireDeclarationOpen(host, "contextWrap")
            return declarations.declareContextWrap(
                ensureHostDeclarations(record),
                "host.hooks.contextWrap",
                path,
                keyOrContext,
                maybeContext
            )
        end,
    }
end

return author
