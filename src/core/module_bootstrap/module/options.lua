local deps = ...

local logging = deps.logging

local options = {}

local KnownModuleOpts = {
    pluginGuid = true,
    config = true,
    modpack = true,
    id = true,
    name = true,
    shortName = true,
    tooltip = true,
}

function options.validateKnown(opts)
    for key in pairs(opts) do
        if key == "definition" then
            logging.violate(
                "module.unknown_opt",
                "createModule: definition table is no longer supported; put definition fields at top level"
            )
        end
        if not KnownModuleOpts[key] then
            logging.violate("module.unknown_opt", "createModule: unknown option '%s'", tostring(key))
        end
    end
end

function options.validateIdentity(opts)
    if type(opts.config) ~= "table" then
        logging.violate("module.invalid_create_opts", "createModule: config is required")
    end
    if type(opts.pluginGuid) ~= "string" or opts.pluginGuid == "" then
        logging.violate("module.invalid_create_opts", "createModule: pluginGuid is required")
    end
end

return options
