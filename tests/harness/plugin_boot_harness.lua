local source = debug.getinfo(1, "S").source
local harnessDir = source:sub(1, 1) == "@"
    and source:sub(2):match("^(.*)[/\\][^/\\]+$")
    or "tests/harness"
local fakeEngine = dofile(harnessDir .. "/fake_engine.lua")

local Harness = {}

local DEFAULT_LIB_GUID = "adamant-ModpackLib"

local function fileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function resolveLibSrcDir(srcDir)
    if type(srcDir) == "string" and srcDir ~= "" then
        return srcDir
    end
    if fileExists("src/main.lua") then
        return "src"
    end
    if fileExists("adamant-ModpackLib/src/main.lua") then
        return "adamant-ModpackLib/src"
    end
    error("libSrcDir is required when Lib src/main.lua is not available from the current directory", 3)
end

local function normalizePlugins(opts)
    if opts.plugins ~= nil then
        return opts.plugins
    end
    if opts.pluginGuid ~= nil or opts.pluginSrcDir ~= nil then
        return {
            {
                guid = opts.pluginGuid,
                srcDir = opts.pluginSrcDir or opts.moduleSrcDir,
                mainPath = opts.pluginMainPath,
                public = opts.pluginPublic,
                imports = opts.pluginImports,
                importOverrides = opts.pluginImportOverrides,
                configureEnv = opts.configurePluginEnv,
            },
        }
    end
    return {}
end

local function assertPlugin(plugin, index)
    assert(type(plugin) == "table", "plugin entry " .. tostring(index) .. " must be a table")
    assert(type(plugin.guid) == "string" and plugin.guid ~= "", "plugin entry " .. tostring(index) .. " guid is required")
    assert(type(plugin.srcDir) == "string" and plugin.srcDir ~= "", "plugin entry " .. tostring(index) .. " srcDir is required")
end

local function runtimeRegistry(libEnv)
    local runtimeRoot = libEnv and libEnv.AdamantModpackLib_Runtime
    return runtimeRoot and runtimeRoot.registry
end

function Harness.boot(opts)
    opts = opts or {}

    local callbacks = opts.callbacks or fakeEngine.createCallbacks()
    local env = fakeEngine.createBaseEnv({
        callbacks = callbacks,
        config = opts.config,
        runtimeRoot = opts.runtimeRoot or {},
        rom = opts.rom,
        chalk = opts.chalk,
        modutilPlugin = opts.modutilPlugin,
        modUtilRuntime = opts.modUtilRuntime,
        withReload = opts.withReload ~= false,
        modUtilWrapMode = opts.modUtilWrapMode or "functional",
        CurrentRun = opts.CurrentRun,
        ScreenData = opts.ScreenData,
        HUDScreen = opts.HUDScreen,
        ShowingCombatUI = opts.ShowingCombatUI,
        ModifyTextBox = opts.ModifyTextBox,
        SetAlpha = opts.SetAlpha,
        CreateComponentFromData = opts.CreateComponentFromData,
        Destroy = opts.Destroy,
        ImGuiComboFlags = opts.ImGuiComboFlags or { NoPreview = 64 },
        ImGuiCol = opts.ImGuiCol,
        ImGuiTreeNodeFlags = opts.ImGuiTreeNodeFlags or {},
    })

    if type(opts.configureEnv) == "function" then
        opts.configureEnv(env, callbacks)
    end

    local libGuid = opts.libGuid or DEFAULT_LIB_GUID
    local libEnv = fakeEngine.loadPlugin(env, libGuid, resolveLibSrcDir(opts.libSrcDir), {
        public = opts.libPublic,
        imports = opts.libImports,
        importOverrides = opts.libImportOverrides,
        plugin = opts.libPlugin or { guid = libGuid },
        register = opts.registerLib ~= false,
    })
    env.lib = libEnv.public
    env.rom.mods[libGuid] = libEnv.public

    local pluginEnvs = {}
    local pluginsByGuid = {}
    for index, plugin in ipairs(normalizePlugins(opts)) do
        assertPlugin(plugin, index)
        if type(plugin.configureEnv) == "function" then
            plugin.configureEnv(env, callbacks)
        end

        local pluginEnv = fakeEngine.loadPlugin(env, plugin.guid, plugin.srcDir, {
            public = plugin.public,
            imports = plugin.imports,
            importOverrides = plugin.importOverrides,
            mainPath = plugin.mainPath,
            plugin = plugin.plugin or { guid = plugin.guid },
            register = plugin.register ~= false,
        })
        pluginEnvs[#pluginEnvs + 1] = pluginEnv
        pluginsByGuid[plugin.guid] = pluginEnv
    end

    local boot = {
        env = env,
        lib = libEnv.public,
        libEnv = libEnv,
        callbacks = callbacks,
        pluginEnvs = pluginEnvs,
        pluginsByGuid = pluginsByGuid,
    }

    function boot:runAllModsLoaded()
        fakeEngine.runAllModsLoaded(self.callbacks)
    end

    function boot:runGameLoaded()
        fakeEngine.runGameLoaded(self.callbacks)
    end

    function boot:runAlwaysDraw()
        fakeEngine.runAlwaysDraw(self.callbacks)
    end

    function boot:getRuntimeRegistry()
        return runtimeRegistry(self.libEnv)
    end

    function boot:getLiveModule(pluginGuid)
        local registry = self:getRuntimeRegistry()
        local modules = registry and registry.modules
        local liveModules = modules and modules.live
        return liveModules and liveModules[pluginGuid] or nil
    end

    if opts.runAllModsLoaded == true then
        boot:runAllModsLoaded()
    end
    if opts.runGameLoaded == true then
        boot:runGameLoaded()
    end
    if opts.runAlwaysDraw == true then
        boot:runAlwaysDraw()
    end

    return boot
end

function Harness.bootModule(opts)
    opts = opts or {}
    assert(type(opts.pluginGuid) == "string", "bootModule pluginGuid is required")
    assert(type(opts.moduleSrcDir) == "string", "bootModule moduleSrcDir is required")

    local bootOpts = {}
    for key, value in pairs(opts) do
        bootOpts[key] = value
    end
    bootOpts.runGameLoaded = opts.runGameLoaded ~= false
    bootOpts.plugins = {
        {
            guid = opts.pluginGuid,
            srcDir = opts.moduleSrcDir,
            mainPath = opts.mainPath,
            public = opts.public,
            imports = opts.imports,
            importOverrides = opts.importOverrides,
            configureEnv = opts.configurePluginEnv,
        },
    }

    local boot = Harness.boot(bootOpts)
    boot.moduleEnv = boot.pluginsByGuid[opts.pluginGuid]
    boot.liveModule = boot:getLiveModule(opts.pluginGuid)
    return boot
end

return Harness
