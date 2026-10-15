local deps = ...

local logging = deps.logging
local coordination = deps.coordination
local overlays = deps.overlays
local createSystem = deps.createSystem
local createTheme = deps.createTheme
local fallbackRegistry = deps.fallbackRegistry
local receipt = deps.receipt
local rom = deps.rom
local modutil = deps.modutil
local uiSession = deps.uiSession
local SetupRunData = deps.gameDeps.runData.SetupRunData
local createModuleFrame = deps.createModuleFrame

local DEFAULT_WINDOW_WIDTH = 960
local DEFAULT_WINDOW_HEIGHT = 720

-- Hot-reload-stable fallback UI runtime. Bridges and GUI callbacks late-read
-- this table so replacement managed modules can swap behavior without new handles.
fallbackRegistry.bridges = fallbackRegistry.bridges or {}
fallbackRegistry.guiAttached = fallbackRegistry.guiAttached or {}
fallbackRegistry.runtimes = fallbackRegistry.runtimes or {}

local bridges = fallbackRegistry.bridges
local guiAttached = fallbackRegistry.guiAttached
local runtimes = fallbackRegistry.runtimes
local fallbackUi = {}
local theme = nil

local function getTheme()
    -- Created lazily because it reads rom.ImGui / rom.ImGuiCol, which may not exist at module creation.
    theme = theme or createTheme()
    return theme
end

local fallbackHud = import('core/fallback/fallback_hud.lua', nil, {
    coordination = coordination,
    overlays = overlays,
    createSystem = createSystem,
    runtimes = runtimes,
})

local function disposeFallbackUiRuntime(ownerId, activeRuntime)
    local closeOk, closeErr = pcall(activeRuntime.handleGuiClosed)

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
    if existing ~= nil then
        return existing
    end
    -- Late-reads the owner's current runtime so a replacement module swaps behavior in place.
    local function callRuntime(method)
        local activeRuntime = runtimes[ownerId]
        if activeRuntime ~= nil then
            return activeRuntime[method]()
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

--- Hands `register` the owner's hot-reload-stable GUI bridge, once per owner id per process.
--- Callers validate `register` at declaration time; whether this owner then installs a fallback
--- runtime is the activating module's decision (`fallbackUiRequested`), not this call's.
---@param ownerId string
---@param register fun(bridge: AdamantModpackLib.FallbackUiBridge)
---@return boolean attached
function fallbackUi.attachGuiOnce(ownerId, register)
    local bridge = getOrCreateBridge(ownerId)
    if guiAttached[ownerId] == true then
        return false
    end

    register(bridge)
    guiAttached[ownerId] = true
    return true
end

local function isCoordinated(packId)
    return packId and coordination.isRegistered(packId) or false
end

---@class AdamantModpackLib.FallbackUiRuntime
---@field module AdamantModpackLib.ManagedModule
---@field session AdamantModpackLib.UiSession
---@field showWindow boolean
---@field didSeedWindowSize boolean
---@field controls { initialized: boolean, enabled: boolean, debug: boolean } Window checkbox state.
---@field frame AdamantModpackLib.ModuleFrame Shared module frame (Enabled, header, module tabs, Hotkeys & Advanced).
---@field renderWindow fun()
---@field addMenuBar fun()
---@field handleGuiClosed fun()

---@param runtime AdamantModpackLib.FallbackUiRuntime
local function markRunDataDirty(runtime)
    if runtime.module.affectsRunData() then
        runtime.session.markRunDataDirty()
    end
end

---@param runtime AdamantModpackLib.FallbackUiRuntime
local function snapshotControls(runtime)
    local controls = runtime.controls
    controls.enabled = runtime.module.isEnabled() == true
    controls.debug = runtime.module.read("DebugMode") == true
    controls.initialized = true
end

---@param runtime AdamantModpackLib.FallbackUiRuntime
local function ensureControlsInitialized(runtime)
    if not runtime.controls.initialized then
        snapshotControls(runtime)
    end
end

---@param runtime AdamantModpackLib.FallbackUiRuntime
local function closeSession(runtime)
    runtime.session.flushRunData()
    runtime.session.releaseOverlays()
end

---@param runtime AdamantModpackLib.FallbackUiRuntime
local function setWindowOpen(runtime, open)
    open = open == true
    if runtime.showWindow == open then
        return
    end

    if open then
        runtime.showWindow = true
        ensureControlsInitialized(runtime)
        runtime.session.suppressOverlays()
        return
    end

    runtime.session.flushRunData()
    runtime.showWindow = false
    runtime.session.releaseOverlays()
end

---@param runtime AdamantModpackLib.FallbackUiRuntime
local function seedWindowSize(runtime, imgui)
    if runtime.didSeedWindowSize then
        return
    end
    imgui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
    runtime.didSeedWindowSize = true
end

local function moduleLabel(module)
    local meta = module.getMeta() or {}
    return tostring(meta.name or module.getModuleId() or "module")
end

--- Fallback paths behind the shared module frame: enable through `module.setEnabled`, the frame's
--- one commit per draw through `commitIfDirty`, Debug Mode and Resync on the module itself.
---@param runtime AdamantModpackLib.FallbackUiRuntime
---@return AdamantModpackLib.ModuleFrameOps
local function createFrameOps(runtime)
    local module = runtime.module
    local controls = runtime.controls
    return {
        isEnabled = function()
            return controls.enabled
        end,
        setEnabled = function(enabled)
            local transitionOk, transitionErr = module.setEnabled(enabled)
            if transitionOk then
                controls.enabled = enabled == true
                markRunDataDirty(runtime)
            else
                logging.violate("managed_module.enable_transition_failed", "%s %s failed: %s",
                    moduleLabel(module),
                    enabled and "enable" or "disable",
                    tostring(transitionErr))
            end
        end,
        getModule = function()
            return module
        end,
        commit = function()
            local commitOk, commitErr, committed = module.commitIfDirty()
            if commitOk and committed and module.isEnabled() then
                markRunDataDirty(runtime)
            elseif commitOk == false then
                logging.violate(
                    "managed_module.staged_state_commit_failed",
                    "%s staged state commit failed; restored previous config where possible: %s",
                    moduleLabel(module),
                    tostring(commitErr)
                )
            end
        end,
        isDebugMode = function()
            return controls.debug
        end,
        setDebugMode = function(enabled)
            module.setDebugMode(enabled)
            controls.debug = enabled == true
        end,
        resync = function()
            module.resync()
            snapshotControls(runtime)
        end,
    }
end

---@param runtime AdamantModpackLib.FallbackUiRuntime
local function renderWindow(runtime)
    local module = runtime.module
    local moduleId = module.getModuleId()
    local meta = module.getMeta() or {}
    if isCoordinated(module.getPackId()) then
        return
    end
    if not runtime.showWindow then
        return
    end

    runtime.session.suppressOverlays()

    local imgui = rom.ImGui
    local activeTheme = getTheme()
    local title = tostring(meta.name or moduleId or "Module") .. "###" .. tostring(moduleId)
    local beganWindow = false
    local openState = runtime.showWindow

    activeTheme.PushTheme()
    local ok, err = xpcall(function()
        ensureControlsInitialized(runtime)
        seedWindowSize(runtime, imgui)
        local shouldDraw
        openState, shouldDraw = imgui.Begin(title, runtime.showWindow)
        beganWindow = true
        if shouldDraw then
            runtime.frame.draw(imgui)
        end
    end, debug.traceback)

    if beganWindow then
        imgui.End()
    end
    activeTheme.PopTheme()

    if not ok then
        error(err)
    end

    if openState == false then
        setWindowOpen(runtime, false)
    end
end

---@param runtime AdamantModpackLib.FallbackUiRuntime
local function drawMenuBar(runtime)
    local packId = runtime.module.getPackId()
    if isCoordinated(packId) then
        local displayName = coordination.getDisplayName(packId) or packId
        rom.ImGui.TextDisabled("Settings are in " .. displayName .. " Modpack Menu")
        return
    end
    if rom.ImGui.MenuItem("Show Mod Menu") then
        setWindowOpen(runtime, not runtime.showWindow)
    end
end

---@param module AdamantModpackLib.ManagedModule
---@return AdamantModpackLib.FallbackUiRuntime
local function createRuntime(module)
    ---@type AdamantModpackLib.FallbackUiRuntime
    local runtime = {
        module = module,
        session = uiSession.create(SetupRunData, overlays),
        showWindow = false,
        didSeedWindowSize = false,
        controls = {
            initialized = false,
            enabled = false,
            debug = false,
        },
    }
    runtime.frame = createModuleFrame(module.getOwnerId(), createFrameOps(runtime))
    -- Zero-argument entry points: hot-reload-stable bridges call these by name.
    function runtime.renderWindow()
        return renderWindow(runtime)
    end
    function runtime.addMenuBar()
        return drawMenuBar(runtime)
    end
    function runtime.handleGuiClosed()
        return closeSession(runtime)
    end
    return runtime
end

---@param ownerId string
---@param module AdamantModpackLib.ManagedModule Live module the fallback window drives.
---@return AdamantModpackLib.Receipt
function fallbackUi.install(ownerId, module)
    local activeRuntime = createRuntime(module)
    local previousRuntime = nil

    return receipt.create({
        name = "fallbackUi",
        phase = receipt.PHASE_EFFECTS,
        commit = function()
            previousRuntime = runtimes[ownerId]
            if previousRuntime and previousRuntime ~= activeRuntime then
                local disposeOk, disposeErr = disposeFallbackUiRuntime(ownerId, previousRuntime)
                if not disposeOk then
                    warnFallbackUiRuntimeDispose(ownerId, disposeErr)
                end
            end
            runtimes[ownerId] = activeRuntime
            fallbackHud.refreshMarker()
            return true, nil
        end,
        rollback = function()
            local ok, err = disposeFallbackUiRuntime(ownerId, activeRuntime)
            if ok and previousRuntime and previousRuntime ~= activeRuntime
                and runtimes[ownerId] == nil then
                runtimes[ownerId] = previousRuntime
                fallbackHud.refreshMarker()
            end
            return ok, err
        end,
        -- Retire never reinstates the runtime this install replaced, and leaves alone a
        -- runtime a successor already installed (its commit closed this one).
        retire = function()
            if runtimes[ownerId] ~= activeRuntime then
                return true, nil
            end
            return disposeFallbackUiRuntime(ownerId, activeRuntime)
        end,
    })
end

function fallbackUi.handleGuiClosed()
    for _, activeRuntime in pairs(runtimes) do
        activeRuntime.handleGuiClosed()
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

    -- Registered once per process; the callback late-reads `wasGuiOpen` and `handleGuiClosed`
    -- from the anchor so a Lib re-import swaps the close handler without re-registering.
    local function handleGuiClosed()
        fallbackRegistry.handleGuiClosed()
    end
    fallbackRegistry.guiCloseWatcherRegistered = true
    fallbackRegistry.wasGuiOpen = rom.gui.is_open() == true
    rom.gui.add_always_draw_imgui(function()
        uiSession.trackGuiClose(fallbackRegistry, rom.gui.is_open() == true, handleGuiClosed)
    end)
end

fallbackRegistry.handleGuiClosed = fallbackUi.handleGuiClosed

installGuiCloseWatcher()

modutil.once_loaded.game(function()
    fallbackUi.createFallbackMarker()
end)

return fallbackUi
