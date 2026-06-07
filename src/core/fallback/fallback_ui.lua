local deps = ...

local logging = deps.logging
local moduleRegistry = deps.moduleRegistry
local coordinator = deps.coordinator
local overlays = deps.overlays
local createSystem = deps.createSystem
local fallbackRegistry = deps.fallbackRegistry
local rom = deps.rom
local modutil = deps.modutil
local SetupRunData = deps.gameDeps.runData.SetupRunData

---@class FallbackUiRuntime
---@field module table|nil
---@field renderWindow fun()
---@field addMenuBar fun()
---@field handleGuiClosed fun()

local DEFAULT_WINDOW_WIDTH = 960
local DEFAULT_WINDOW_HEIGHT = 720

-- Hot-reload-stable fallback UI runtime. Bridges and GUI callbacks late-read
-- this table so replacement managed modules can swap behavior without new handles.
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

local function requireModuleRecord(module, apiName)
    local record = moduleRegistry.getRecord(module)
    if not record then
        logging.violate("fallback_ui.invalid_args", "%s: expected managed module", apiName)
    end
    return record
end

local function requireAttachmentOpen(module)
    local record = requireModuleRecord(module, "module.fallbackUi.attachGuiOnce")
    if record.activating == true or record.activated == true then
        logging.violate(
            "fallback_ui.invalid_args",
            "module.fallbackUi.attachGuiOnce cannot be called after activation begins"
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
    if type(activeRuntime.handleGuiClosed) == "function" then
        closeOk, closeErr = pcall(activeRuntime.handleGuiClosed)
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
        "managed_module.retire_failed",
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
        handleGuiClosed = function()
            return callRuntime("handleGuiClosed")
        end,
    }
    bridges[ownerId] = bridge
    return bridge
end

function fallbackUi.attachGuiOnce(module, register)
    if type(register) ~= "function" then
        logging.violate("fallback_ui.invalid_args", "module.fallbackUi.attachGuiOnce: register must be a function")
    end
    local state = requireAttachmentOpen(module)
    local ownerId = module.getOwnerId()
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

local function createRuntime(module)
    local function getMeta()
        return module.getMeta() or {}
    end

    local showWindow = false
    local didSeedWindowSize = false
    local runDataDirty = false
    local uiSuppressionToken = nil

    local function markRunDataDirty()
        if module.affectsRunData() then
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

    local function handleGuiClosed()
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
        local moduleId = module.getModuleId()
        local packId = module.getPackId()
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
            local enabled = module.isEnabled()
            local enabledValue, enabledChanged = imgui.Checkbox("Enabled", enabled)
            if enabledChanged then
                local ok, err = module.setEnabled(enabledValue)
                if ok then
                    enabled = enabledValue == true
                    markRunDataDirty()
                else
                    logging.violate("managed_module.enable_transition_failed", "%s %s failed: %s",
                        tostring(meta.name or moduleId or "module"),
                        enabledValue and "enable" or "disable",
                        tostring(err))
                end
            end

            local debugValue, debugChanged = imgui.Checkbox("Debug Mode", module.read("DebugMode") == true)
            if debugChanged then
                module.setDebugMode(debugValue)
            end

            if imgui.Button("Resync State") then
                module.resync()
            end

            if enabled then
                imgui.Separator()
                imgui.Spacing()
                local ok, err, committed = module.drawTabAndCommit()
                if ok and committed and module.isEnabled() then
                    markRunDataDirty()
                elseif ok == false then
                    logging.violate(
                        "managed_module.staged_state_commit_failed",
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
        local packId = module.getPackId()
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
        module = module,
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
        handleGuiClosed = handleGuiClosed,
    }
    return activeRuntime
end

function fallbackUi.installForModule(module)
    local ownerId = module.getOwnerId()
    local activeRuntime = createRuntime(module)
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

function fallbackUi.create(module)
    return {
        attachGuiOnce = function(register)
            return fallbackUi.attachGuiOnce(module, register)
        end
    }
end

function fallbackUi.handleGuiClosed()
    for _, activeRuntime in pairs(runtimes) do
        if type(activeRuntime.handleGuiClosed) == "function" then
            activeRuntime.handleGuiClosed()
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
            and type(fallbackRegistry.handleGuiClosed) == "function" then
            fallbackRegistry.handleGuiClosed()
        end
        fallbackRegistry.wasGuiOpen = isGuiOpen
    end)
end

fallbackRegistry.handleGuiClosed = fallbackUi.handleGuiClosed

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
