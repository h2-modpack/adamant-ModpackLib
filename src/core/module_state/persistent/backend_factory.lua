local deps = ...

local chalk = deps.chalk
local logging = deps.logging
local rom = deps.rom

local backendFactory = {}

local backendMetrics = import('core/module_state/persistent/backend_metrics.lua', nil, {
    logging = logging,
})

local chalkBackend = import('core/module_state/persistent/backend.lua', nil, {
    chalk = chalk,
    metrics = backendMetrics,
})

local nativeBackend = import('core/module_state/persistent/native_backend.lua', nil, {
    metrics = backendMetrics,
})

local function resolveNativeConfigPath(pluginGuid)
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        return nil
    end
    if type(rom) ~= "table" or type(rom.paths) ~= "table" or type(rom.path) ~= "table"
        or type(rom.paths.config) ~= "function" or type(rom.path.combine) ~= "function" then
        return nil
    end

    local configOk, configRoot = pcall(rom.paths.config)
    if not configOk or type(configRoot) ~= "string" or configRoot == "" then
        return nil
    end

    local combineOk, path = pcall(rom.path.combine, configRoot, pluginGuid .. ".cfg")
    if combineOk and type(path) == "string" and path ~= "" then
        return path
    end
    return nil
end

function backendFactory.create(modConfig, opts)
    opts = opts or {}
    local nativeConfigPath = type(opts.configPath) == "string" and opts.configPath ~= ""
        and opts.configPath
        or resolveNativeConfigPath(opts.pluginGuid)
    local backend = nativeBackend.create({
        path = nativeConfigPath,
    })
    if backend then
        return backend
    end
    return chalkBackend.create(modConfig)
end

return backendFactory
