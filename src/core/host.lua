local internal = AdamantModpackLib_Internal

---@class StandaloneOpts
---@field windowTitle string|nil

---@class StandaloneRuntime
---@field renderWindow fun()
---@field addMenuBar fun()

---@class AuthorSession
---@field view table<string, any>
---@field read fun(alias: string): any
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)
---@field resetToDefaults fun(opts: table|nil): boolean, number

---@class ModuleHostOpts
---@field definition ModuleDefinition
---@field moduleName string|nil
---@field store ManagedStore
---@field session Session
---@field hookOwner table|nil
---@field registerHooks fun()|nil
---@field drawTab fun(imgui: table, session: AuthorSession)
---@field drawQuickContent fun(imgui: table, session: AuthorSession)|nil

---@class ModuleHost
---@field getIdentity fun(): table
---@field getMeta fun(): table
---@field affectsRunData fun(): boolean
---@field getHashHints fun(): table|nil
---@field getStorage fun(): StorageSchema|nil
---@field read fun(aliasOrKey: ConfigPath): any
---@field writeAndFlush fun(aliasOrKey: ConfigPath, value: any): boolean
---@field stage fun(aliasOrKey: ConfigPath, value: any): boolean
---@field flush fun(): boolean
---@field reloadFromConfig fun()
---@field resync fun(): string[]
---@field resetToDefaults fun(opts: table|nil): boolean, number
---@field commitIfDirty fun(): boolean, string|nil, boolean
---@field isEnabled fun(): boolean
---@field setEnabled fun(enabled: boolean): boolean, string|nil
---@field setDebugMode fun(enabled: boolean)
---@field applyOnLoad fun(): boolean, string|nil
---@field applyMutation fun(): boolean, string|nil
---@field revertMutation fun(): boolean, string|nil
---@field drawTab fun(imgui: table)
---@field drawQuickContent fun(imgui: table)|nil

function public.getLiveModuleHost(moduleName)
    if type(moduleName) ~= "string" or moduleName == "" then
        return nil
    end
    return internal.liveModuleHosts[moduleName]
end

function public.getLiveModuleHostById(packId, moduleId)
    if type(packId) ~= "string" or packId == "" then
        return nil
    end
    if type(moduleId) ~= "string" or moduleId == "" then
        return nil
    end
    local packHosts = internal.liveModuleHostsByPack[packId]
    return type(packHosts) == "table" and packHosts[moduleId] or nil
end

--- Creates a behavior-only host object for Framework and standalone hosting.
--- Registers the created host into Lib's live-host registry under `opts.moduleName`
--- (or the current `_PLUGIN.guid`) so coordinated discovery can resolve it immediately.
--- The host closes over store/session without exposing those state handles publicly.
---@param opts ModuleHostOpts
---@return ModuleHost host Module host behavior contract.
function public.createModuleHost(opts)
    assert(type(opts) == "table", "createModuleHost: opts must be a table")
    local def = opts.definition
    local store = opts.store
    local session = opts.session
    assert(type(def) == "table", "createModuleHost: definition is required")
    assert(store and type(store.read) == "function", "createModuleHost: store is required")
    assert(session and type(session.isDirty) == "function" and type(session.write) == "function",
        "createModuleHost: session is required")

    local drawTab = opts.drawTab
    local drawQuickContent = opts.drawQuickContent
    local registerHooks = opts.registerHooks
    local hookOwner = opts.hookOwner
    local moduleName = opts.moduleName

    assert(type(drawTab) == "function", "createModuleHost: drawTab is required")
    if moduleName == nil and type(_PLUGIN) == "table" then
        moduleName = _PLUGIN.guid
    end
    assert(type(moduleName) == "string" and moduleName ~= "",
        "createModuleHost: moduleName is required (or _PLUGIN.guid must be available)")

    if registerHooks ~= nil then
        assert(type(registerHooks) == "function", "createModuleHost: registerHooks must be a function")
        assert(type(hookOwner) == "table", "createModuleHost: hookOwner is required when registerHooks is provided")
        internal.hooks.refresh(hookOwner, registerHooks)
    end

    ---@type AuthorSession
    local authorSession = {
        view = session.view,
        read = session.read,
        write = session.write,
        reset = session.reset,
        resetToDefaults = function(resetOpts)
            return public.resetStorageToDefaults(def.storage, session, resetOpts)
        end,
    }

    ---@type ModuleHost
    local host = {}

    function host.getIdentity()
        return {
            id = def.id,
            modpack = def.modpack,
        }
    end

    function host.getMeta()
        return {
            name = def.name,
            shortName = def.shortName,
            tooltip = def.tooltip,
        }
    end

    function host.affectsRunData()
        return public.lifecycle.affectsRunData(def)
    end

    function host.getHashHints()
        return def.hashGroupPlan
    end

    function host.getStorage()
        return def.storage
    end

    function host.read(aliasOrKey)
        return store.read(aliasOrKey)
    end

    function host.writeAndFlush(aliasOrKey, value)
        session.write(aliasOrKey, value)
        session._flushToConfig()
        return true
    end

    function host.stage(aliasOrKey, value)
        session.write(aliasOrKey, value)
        return true
    end

    function host.flush()
        session._flushToConfig()
        return true
    end

    function host.reloadFromConfig()
        session._reloadFromConfig()
    end

    function host.resync()
        return public.lifecycle.resyncSession(def, session)
    end

    function host.resetToDefaults(resetOpts)
        return public.resetStorageToDefaults(def.storage, session, resetOpts)
    end

    function host.commitIfDirty()
        if not session.isDirty() then
            return true, nil, false
        end
        local ok, err = public.lifecycle.commitSession(def, store, session)
        return ok, err, ok == true
    end

    function host.isEnabled()
        return public.isModuleEnabled(store, host.getIdentity().modpack)
    end

    function host.setEnabled(enabled)
        return public.lifecycle.setEnabled(def, store, enabled)
    end

    function host.setDebugMode(enabled)
        return public.lifecycle.setDebugMode(store, enabled)
    end

    function host.applyOnLoad()
        return public.lifecycle.applyOnLoad(def, store)
    end

    function host.applyMutation()
        return public.lifecycle.applyMutation(def, store)
    end

    function host.revertMutation()
        return public.lifecycle.revertMutation(def, store)
    end

    function host.drawTab(imgui)
        return drawTab(imgui, authorSession)
    end

    if type(drawQuickContent) == "function" then
        function host.drawQuickContent(imgui)
            return drawQuickContent(imgui, authorSession)
        end
    end

    local identity = host.getIdentity()
    local meta = host.getMeta()
    local packId = identity.modpack
    local moduleId = identity.id
    local pendingCoordinatorRebuild = internal.pendingCoordinatorRebuilds[def]
    local hasPendingCoordinatorRebuild = type(pendingCoordinatorRebuild) == "table"
    internal.liveModuleHosts[moduleName] = host
    if type(packId) == "string" and packId ~= "" and type(moduleId) == "string" and moduleId ~= "" then
        local packHosts = internal.liveModuleHostsByPack[packId]
        if type(packHosts) ~= "table" then
            packHosts = {}
            internal.liveModuleHostsByPack[packId] = packHosts
        end
        packHosts[moduleId] = host
    end
    if not hasPendingCoordinatorRebuild
        and type(packId) == "string"
        and packId ~= ""
        and public.isModuleCoordinated(packId) then
        local ok, err = host.applyOnLoad()
        if not ok then
            internal.logging.warn("%s coordinated runtime sync failed: %s",
                tostring(meta.name or identity.id or "module"),
                tostring(err))
        end
    elseif hasPendingCoordinatorRebuild then
        local requested = public.lifecycle.requestCoordinatorRebuild(packId, pendingCoordinatorRebuild)
        if requested then
            internal.pendingCoordinatorRebuilds[def] = nil
        else
            internal.logging.warn("%s structural definition changed during hot reload; full reload required",
                tostring(meta.name or identity.id or "module"))
        end
    end

    return host
end

--- Initializes standalone module hosting and returns window/menu-bar renderers.
---@param packId string|nil Explicit pack id, or nil to resolve the current module by `_PLUGIN.guid`.
---@param moduleIdOrOpts string|StandaloneOpts|nil Explicit module id, or opts when using the zero-arg current-module form.
---@param opts StandaloneOpts|nil Optional standalone rendering hooks and window settings.
---@return StandaloneRuntime runtime Standalone runtime with `renderWindow` and `addMenuBar` callbacks.
function public.standaloneHost(packId, moduleIdOrOpts, opts)
    local moduleHost
    if type(packId) == "string" and packId ~= "" then
        assert(type(moduleIdOrOpts) == "string" and moduleIdOrOpts ~= "",
            "standaloneHost: moduleId is required when packId is provided")
        moduleHost = public.getLiveModuleHostById(packId, moduleIdOrOpts)
        assert(type(moduleHost) == "table",
            string.format("standaloneHost: no live module host is registered for '%s/%s'",
                tostring(packId), tostring(moduleIdOrOpts)))
    else
        if packId ~= nil then
            opts = packId
        elseif moduleIdOrOpts ~= nil then
            opts = moduleIdOrOpts
        end
        local moduleName = type(_PLUGIN) == "table" and _PLUGIN.guid or nil
        assert(type(moduleName) == "string" and moduleName ~= "",
            "standaloneHost: current module guid is unavailable")
        moduleHost = public.getLiveModuleHost(moduleName)
        assert(type(moduleHost) == "table",
            string.format("standaloneHost: no live module host is registered for current module '%s'",
                tostring(moduleName)))
    end

    opts = opts or {}
    assert(type(moduleHost.getIdentity) == "function" and type(moduleHost.getMeta) == "function",
        "standaloneHost: moduleHost metadata accessors are required")
    local DEFAULT_WINDOW_WIDTH = 960
    local DEFAULT_WINDOW_HEIGHT = 720

    local function getIdentity()
        return moduleHost.getIdentity() or {}
    end

    local function getMeta()
        return moduleHost.getMeta() or {}
    end

    if not (getIdentity().modpack and internal.coordinators[getIdentity().modpack]) then
        local ok, err = moduleHost.applyOnLoad()
        if not ok then
            internal.logging.warn("%s startup lifecycle failed: %s",
                tostring(getMeta().name or getIdentity().id or "module"),
                tostring(err))
        end
    end

    local showWindow = false
    local didSeedWindowSize = false
    local runDataDirty = false

    local function markRunDataDirty()
        if moduleHost.affectsRunData() then
            runDataDirty = true
        end
    end

    local function flushPendingRunData()
        if not runDataDirty then
            return
        end
        rom.game.SetupRunData()
        runDataDirty = false
    end

    local function seedWindowSize(imgui)
        if didSeedWindowSize then
            return
        end
        imgui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
        didSeedWindowSize = true
    end

    local function renderWindow()
        local identity = getIdentity()
        local meta = getMeta()
        if identity.modpack and internal.coordinators[identity.modpack] then return end
        if not showWindow then return end

        local imgui = rom.ImGui
        local title = (opts.windowTitle or meta.name) .. "###" .. tostring(identity.id)
        seedWindowSize(imgui)
        local open, shouldDraw = imgui.Begin(title, showWindow)
        if shouldDraw then
            local enabled = moduleHost.read("Enabled") == true
            local enabledValue, enabledChanged = imgui.Checkbox("Enabled", enabled)
            if enabledChanged then
                local ok, err = moduleHost.setEnabled(enabledValue)
                if ok then
                    markRunDataDirty()
                else
                    internal.logging.warn("%s %s failed: %s",
                        tostring(meta.name or identity.id or "module"),
                        enabledValue and "enable" or "disable",
                        tostring(err))
                end
            end

            local debugValue, debugChanged = imgui.Checkbox("Debug Mode", moduleHost.read("DebugMode") == true)
            if debugChanged then
                moduleHost.setDebugMode(debugValue)
            end

            if imgui.Button("Resync Session") then
                moduleHost.resync()
            end

            imgui.Separator()
            imgui.Spacing()
            moduleHost.drawTab(imgui)
            local ok, err, committed = moduleHost.commitIfDirty()
            if ok and committed and moduleHost.read("Enabled") == true then
                markRunDataDirty()
            elseif ok == false then
                internal.logging.warn("%s session commit failed; restored previous config where possible: %s",
                    tostring(meta.name or identity.id or "module"),
                    tostring(err))
            end
        end
        imgui.End()
        if open == false then
            flushPendingRunData()
            showWindow = false
        end
    end

    local function addMenuBar()
        local identity = getIdentity()
        local meta = getMeta()
        if identity.modpack and internal.coordinators[identity.modpack] then return end
        if rom.ImGui.BeginMenu(meta.name) then
            if rom.ImGui.MenuItem(meta.name) then
                if showWindow then
                    flushPendingRunData()
                end
                showWindow = not showWindow
            end
            rom.ImGui.EndMenu()
        end
    end

    return {
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
    }
end
