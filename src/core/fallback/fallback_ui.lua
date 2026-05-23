local deps = ...

local logging = deps.logging
local hostRegistry = deps.hostRegistry
local coordinator = deps.coordinator
local overlays = deps.overlays
local createSystem = deps.createSystem
local fallbackRegistry = deps.fallbackRegistry
local rom = deps.rom
local modutil = deps.modutil
local SetupRunData = deps.gameDeps.runData.SetupRunData

---@class FallbackUiRuntime
---@field host table|nil
---@field renderWindow fun()
---@field addMenuBar fun()
---@field handleHostGuiClosed fun()

local DEFAULT_WINDOW_WIDTH = 960
local DEFAULT_WINDOW_HEIGHT = 720

-- Hot-reload-stable fallback UI runtime. Bridges and GUI callbacks late-read
-- this table so replacement module hosts can swap behavior without new handles.
fallbackRegistry.bridges = fallbackRegistry.bridges or {}
fallbackRegistry.guiAttached = fallbackRegistry.guiAttached or {}
fallbackRegistry.runtimes = fallbackRegistry.runtimes or {}
fallbackRegistry.fallbackHud = fallbackRegistry.fallbackHud or {}

local bridges = fallbackRegistry.bridges
local guiAttached = fallbackRegistry.guiAttached
local runtimes = fallbackRegistry.runtimes
local fallbackUi = {}

local fallbackHud = import('core/fallback/fallback_hud.lua', nil, {
    coordinator = coordinator,
    overlays = overlays,
    createSystem = createSystem,
    runtimes = runtimes,
    state = fallbackRegistry.fallbackHud,
})

local function requireHostRecord(host, apiName)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("fallback_ui.invalid_args", "%s: expected managed module host", apiName)
    end
    return record
end

local function requireAttachmentOpen(host)
    local record = requireHostRecord(host, "host.fallbackUi.attachGuiOnce")
    if record.activating == true or record.activated == true then
        logging.violate(
            "fallback_ui.invalid_args",
            "host.fallbackUi.attachGuiOnce cannot be called after activation begins"
        )
    end
    return record
end

local function getFallbackUiRuntime(ownerId)
    local activeRuntime = runtimes[ownerId]
    if type(activeRuntime) ~= "table" then
        return nil
    end
    return activeRuntime
end

local function disposeFallbackUiRuntime(ownerId, activeRuntime)
    if type(activeRuntime) ~= "table" then
        return true, nil
    end

    local closeOk, closeErr = true, nil
    if type(activeRuntime.handleHostGuiClosed) == "function" then
        closeOk, closeErr = pcall(activeRuntime.handleHostGuiClosed)
    end

    if runtimes[ownerId] == activeRuntime then
        runtimes[ownerId] = nil
        fallbackHud.refreshMarker()
    end

    if not closeOk then
        return false, closeErr
    end
    return true, nil
end

local function warnFallbackUiRuntimeDispose(ownerId, err)
    logging.violate(
        "host.retire_failed",
        "fallback UI runtime '%s' retirement failed: %s",
        tostring(ownerId),
        tostring(err)
    )
end

local function getOrCreateBridge(ownerId)
    local existing = bridges[ownerId]
    if type(existing) == "table" then
        return existing
    end
    local function callRuntime(method)
        local activeRuntime = getFallbackUiRuntime(ownerId)
        local callback = activeRuntime and activeRuntime[method] or nil
        if type(callback) == "function" then
            return callback()
        end
    end

    local bridge = {
        renderWindow = function()
            return callRuntime("renderWindow")
        end,
        addMenuBar = function()
            return callRuntime("addMenuBar")
        end,
        handleHostGuiClosed = function()
            return callRuntime("handleHostGuiClosed")
        end,
    }
    bridges[ownerId] = bridge
    return bridge
end

function fallbackUi.attachGuiOnce(host, register)
    if type(register) ~= "function" then
        logging.violate("fallback_ui.invalid_args", "host.fallbackUi.attachGuiOnce: register must be a function")
    end
    local state = requireAttachmentOpen(host)
    local ownerId = host.getHostId()
    state.fallbackUiRequested = true
    local bridge = getOrCreateBridge(ownerId)
    if guiAttached[ownerId] == true then
        return false
    end

    register(bridge)
    guiAttached[ownerId] = true
    return true
end

local function isCoordinated(packId)
    return packId and coordinator.isRegistered(packId) or false
end

local function createRuntime(host)
    local function getMeta()
        return host.getMeta() or {}
    end

    local showWindow = false
    local didSeedWindowSize = false
    local runDataDirty = false
    local uiSuppressionToken = nil

    local function markRunDataDirty()
        if host.affectsRunData() then
            runDataDirty = true
        end
    end

    local function flushPendingRunData()
        if not runDataDirty then
            return
        end
        SetupRunData()
        runDataDirty = false
    end

    local function suppressOverlays()
        if not uiSuppressionToken then
            uiSuppressionToken = overlays.suppressForUi()
        end
    end

    local function releaseOverlaySuppression()
        if uiSuppressionToken then
            uiSuppressionToken.release()
            uiSuppressionToken = nil
        end
    end

    local function handleHostGuiClosed()
        flushPendingRunData()
        releaseOverlaySuppression()
    end

    local function setWindowOpen(open)
        open = open == true
        if showWindow == open then
            return
        end

        if open then
            showWindow = true
            suppressOverlays()
            return
        end

        flushPendingRunData()
        showWindow = false
        releaseOverlaySuppression()
    end

    local function seedWindowSize(imgui)
        if didSeedWindowSize then
            return
        end
        imgui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
        didSeedWindowSize = true
    end

    local function renderWindow()
        local moduleId = host.getModuleId()
        local packId = host.getPackId()
        local meta = getMeta()
        if isCoordinated(packId) then
            return
        end
        if not showWindow then
            return
        end

        suppressOverlays()

        local imgui = rom.ImGui
        local title = tostring(meta.name or moduleId or "Module") .. "###" .. tostring(moduleId)
        seedWindowSize(imgui)
        local open, shouldDraw = imgui.Begin(title, showWindow)
        if shouldDraw then
            local enabled = host.isEnabled()
            local enabledValue, enabledChanged = imgui.Checkbox("Enabled", enabled)
            if enabledChanged then
                local ok, err = host.setEnabled(enabledValue)
                if ok then
                    enabled = enabledValue == true
                    markRunDataDirty()
                else
                    logging.violate("host.enable_transition_failed", "%s %s failed: %s",
                        tostring(meta.name or moduleId or "module"),
                        enabledValue and "enable" or "disable",
                        tostring(err))
                end
            end

            local debugValue, debugChanged = imgui.Checkbox("Debug Mode", host.read("DebugMode") == true)
            if debugChanged then
                host.setDebugMode(debugValue)
            end

            if imgui.Button("Resync State") then
                host.resync()
            end

            if enabled then
                imgui.Separator()
                imgui.Spacing()
                host.drawTab()
                local ok, err, committed = host.commitIfDirty()
                if ok and committed and host.isEnabled() then
                    markRunDataDirty()
                elseif ok == false then
                    logging.violate(
                        "host.staged_state_commit_failed",
                        "%s staged state commit failed; restored previous config where possible: %s",
                        tostring(meta.name or moduleId or "module"),
                        tostring(err)
                    )
                end
            end
        end
        imgui.End()
        if open == false then
            setWindowOpen(false)
        end
    end

    local function addMenuBar()
        local packId = host.getPackId()
        local meta = getMeta()
        if isCoordinated(packId) then return end
        if rom.ImGui.BeginMenu(meta.name) then
            if rom.ImGui.MenuItem(meta.name) then
                setWindowOpen(not showWindow)
            end
            rom.ImGui.EndMenu()
        end
    end

    local activeRuntime = {
        host = host,
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
        handleHostGuiClosed = handleHostGuiClosed,
    }
    return activeRuntime
end

function fallbackUi.installForHost(host)
    local ownerId = host.getHostId()
    local activeRuntime = createRuntime(host)
    local previousRuntime = nil
    local installed = false

    return {
        commit = function()
            previousRuntime = getFallbackUiRuntime(ownerId)
            if previousRuntime and previousRuntime ~= activeRuntime then
                local disposeOk, disposeErr = disposeFallbackUiRuntime(ownerId, previousRuntime)
                if not disposeOk then
                    warnFallbackUiRuntimeDispose(ownerId, disposeErr)
                end
            end
            runtimes[ownerId] = activeRuntime
            installed = true
            fallbackHud.refreshMarker()
            return true
        end,
        dispose = function()
            if installed ~= true then
                return true
            end
            local ok, err = disposeFallbackUiRuntime(ownerId, activeRuntime)
            if ok and previousRuntime and previousRuntime ~= activeRuntime
                and getFallbackUiRuntime(ownerId) == nil then
                runtimes[ownerId] = previousRuntime
                fallbackHud.refreshMarker()
            end
            return ok, err
        end,
    }
end

function fallbackUi.create(host)
    return {
        attachGuiOnce = function(register)
            return fallbackUi.attachGuiOnce(host, register)
        end
    }
end

function fallbackUi.handleHostGuiClosed()
    for _, activeRuntime in pairs(runtimes) do
        if type(activeRuntime.handleHostGuiClosed) == "function" then
            activeRuntime.handleHostGuiClosed()
        end
    end
end

function fallbackUi.createFallbackMarker()
    return fallbackHud.createMarker()
end

local function installGuiCloseWatcher()
    if fallbackRegistry.guiCloseWatcherRegistered then
        return
    end
    if not (rom and rom.gui and type(rom.gui.add_always_draw_imgui) == "function"
        and type(rom.gui.is_open) == "function") then
        return
    end

    fallbackRegistry.guiCloseWatcherRegistered = true
    fallbackRegistry.wasGuiOpen = rom.gui.is_open() == true
    rom.gui.add_always_draw_imgui(function()
        local isGuiOpen = rom.gui.is_open() == true
        if fallbackRegistry.wasGuiOpen and not isGuiOpen
            and type(fallbackRegistry.handleHostGuiClosed) == "function" then
            fallbackRegistry.handleHostGuiClosed()
        end
        fallbackRegistry.wasGuiOpen = isGuiOpen
    end)
end

fallbackRegistry.handleHostGuiClosed = fallbackUi.handleHostGuiClosed

installGuiCloseWatcher()

modutil.once_loaded.game(function()
    fallbackUi.createFallbackMarker()
end)

return {
    service = fallbackUi,
    author = {
        create = fallbackUi.create,
    },
    public = {},
}
