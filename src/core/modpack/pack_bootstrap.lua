local deps = ...
local rom = deps.rom
local logging = deps.logging
local libConfig = deps.libConfig
local storage = deps.storage
local coordination = deps.coordination
local overlaySurface = deps.overlaySurface
local getLiveModule = deps.getLiveModule
local profileTools = deps.profileTools
local constructors = deps.constructors
local packRegistry = deps.packRegistry

local function disposePack(pack)
    local packUi = pack and pack.ui
    if not packUi then
        return
    end

    if packUi.dispose ~= nil then
        packUi.dispose()
    elseif packUi.handleGuiClosed ~= nil then
        packUi.handleGuiClosed()
    end
end

local function validateCreatePackArgs(packId, config, numProfiles, defaultProfiles, opts)
    assert(type(packId) == "string" and packId ~= "",
        "modpack.createPack: packId must be a non-empty string")
    assert(type(config) == "table", "modpack.createPack: config must be a table")
    assert(type(defaultProfiles) == "table",
        "modpack.createPack: defaultProfiles must be a table")
    assert(opts == nil or type(opts) == "table",
        "modpack.createPack: opts must be a table when provided")
    opts = opts or {}
    assert(opts.hideHashMarker == nil or type(opts.hideHashMarker) == "boolean",
        "modpack.createPack: hideHashMarker must be a boolean when provided")
    assert(opts.moduleOrder == nil or type(opts.moduleOrder) == "table",
        "modpack.createPack: opts.moduleOrder must be a table when provided")
    assert(opts.drawPackQuickContent == nil or type(opts.drawPackQuickContent) == "function",
        "modpack.createPack: opts.drawPackQuickContent must be a function when provided")
    assert(type(config.ModEnabled) == "boolean",
        "modpack.createPack: config.ModEnabled must be a boolean")
    assert(type(config.DebugMode) == "boolean",
        "modpack.createPack: config.DebugMode must be a boolean")
    assert(type(numProfiles) == "number" and numProfiles > 0 and math.floor(numProfiles) == numProfiles,
        "modpack.createPack: numProfiles must be a positive integer")

    profileTools.normalizeProfiles(config.Profiles, numProfiles)
    return opts
end

local function validateRuntimePrerequisites()
    assert(rom and type(rom.ImGui) == "table",
        "modpack.createPack: rom.ImGui is not ready; call modpack.createPack after game load")
    assert(rom.game and type(rom.game.SetupRunData) == "function",
        "modpack.createPack: rom.game.SetupRunData is not ready; call modpack.createPack after game load")
end

local function validateCoordinatorArgs(packId, displayName, config, rebuildCallback)
    assert(type(packId) == "string" and packId ~= "",
        "modpack.registerCoordinator: packId must be a non-empty string")
    if config == nil then
        assert(displayName == nil,
            "modpack.registerCoordinator: displayName must be nil when clearing registration")
    else
        assert(type(displayName) == "string" and displayName ~= "",
            "modpack.registerCoordinator: displayName must be a non-empty string")
    end
    assert(config == nil or type(config) == "table",
        "modpack.registerCoordinator: config must be a table when provided")
    assert(config == nil or type(config.ModEnabled) == "boolean",
        "modpack.registerCoordinator: config.ModEnabled must be a boolean")
    assert(rebuildCallback == nil or type(rebuildCallback) == "function",
        "modpack.registerCoordinator: rebuildCallback must be a function when provided")
end

local function registerCoordinator(packId, displayName, config, rebuildCallback)
    validateCoordinatorArgs(packId, displayName, config, rebuildCallback)
    coordination.register(packId, displayName, config)
    coordination.registerRebuild(packId, rebuildCallback)
    return true
end

local function createPackOrThrow(packId, config, numProfiles, defaultProfiles, opts)
    opts = validateCreatePackArgs(packId, config, numProfiles, defaultProfiles, opts)
    validateRuntimePrerequisites()

    assert(coordination.isRegistered(packId),
        "modpack.createPack: coordinator must register before createPack; see Core/main.lua")
    local windowTitle = coordination.getDisplayName(packId)
    assert(type(windowTitle) == "string" and windowTitle ~= "",
        "modpack.createPack: coordinator displayName is missing; register coordinator before createPack")

    local existingPack = packRegistry.packs[packId]
    local packIndex = existingPack and existingPack._index or #packRegistry.packList + 1

    local moduleRegistry = constructors.createModuleRegistry(packId, config, getLiveModule)
    local configHash = constructors.createConfigHash(moduleRegistry, config, packId, storage)
    local theme = constructors.createTheme()
    local auditSavedProfiles = function(auditPackId, profileSlots, auditModuleRegistry)
        return profileTools.auditSavedProfiles(auditPackId, profileSlots, auditModuleRegistry, storage)
    end

    moduleRegistry.refresh(opts.moduleOrder)

    local hud = constructors.createHud(packId, packIndex, configHash, theme, config,
        opts.hideHashMarker == true, overlaySurface)
    local ui = constructors.createUI(moduleRegistry, hud, theme, config, packId, windowTitle,
        numProfiles, defaultProfiles, opts.drawPackQuickContent, auditSavedProfiles, libConfig, overlaySurface)

    auditSavedProfiles(packId, config.Profiles, moduleRegistry)

    local pack = {
        moduleRegistry = moduleRegistry,
        configHash = configHash,
        hud = hud,
        ui = ui,
        _index = packIndex,
    }

    local ok, err = xpcall(function()
        hud.install()
    end, debug.traceback)
    if not ok then
        disposePack(pack)
        error(err, 0)
    end

    disposePack(existingPack)

    if not existingPack then
        table.insert(packRegistry.packList, packId)
    end
    packRegistry.packs[packId] = pack

    if config.ModEnabled then
        hud.setModMarker(true)
    end

    return pack
end

local function createPack(packId, config, numProfiles, defaultProfiles, opts)
    local ok, pack = xpcall(function()
        return createPackOrThrow(packId, config, numProfiles, defaultProfiles, opts)
    end, debug.traceback)

    if ok then
        return true, pack, nil
    end

    local err = tostring(pack)
    local logPackId = type(packId) == "string" and packId ~= "" and packId or "modpack"
    logging.warn(logPackId, "modpack createPack failed; skipping pack: %s", err)
    return false, nil, err
end

local function createGuiCallbacks(packId)
    assert(type(packId) == "string" and packId ~= "",
        "modpack.createGuiCallbacks: packId must be a non-empty string")

    local wasGuiOpen = rom.gui.is_open() == true

    local function render()
        local pack = packRegistry.packs[packId]
        if not pack or not pack.ui then
            return
        end
        pack.ui.renderWindow()
    end

    local function alwaysDraw()
        local isGuiOpen = rom.gui.is_open() == true

        if wasGuiOpen and not isGuiOpen then
            local pack = packRegistry.packs[packId]
            if pack and pack.ui then
                pack.ui.handleGuiClosed()
            end
        end

        wasGuiOpen = isGuiOpen
    end

    local function menuBar()
        local pack = packRegistry.packs[packId]
        if not pack or not pack.ui then
            return
        end
        pack.ui.addMenuBar()
    end

    return {
        render = render,
        alwaysDraw = alwaysDraw,
        menuBar = menuBar,
    }
end

return {
    registerCoordinator = registerCoordinator,
    createPack = createPack,
    createGuiCallbacks = createGuiCallbacks,
}
