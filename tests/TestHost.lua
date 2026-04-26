local lu = require('luaunit')

TestHost = {}

function TestHost:setUp()
    CaptureWarnings()
    self.previousImGui = rom.ImGui
    self.previousImGuiCond = rom.ImGuiCond
end

function TestHost:tearDown()
    rom.ImGui = self.previousImGui
    rom.ImGuiCond = self.previousImGuiCond
    RestoreWarnings()
end

function TestHost:testStandaloneHostWarnsWhenSessionCommitFails()
    local drawCalls = 0

    local function noop() end

    rom.ImGuiCond = { FirstUseEver = 1 }
    rom.ImGui = {
        BeginMenu = function() return true end,
        MenuItem = function() return true end,
        EndMenu = noop,
        SetNextWindowSize = noop,
        Begin = function() return true, true end,
        End = noop,
        Checkbox = function(_, current) return current, false end,
        Button = function() return false end,
        Separator = noop,
        Spacing = noop,
    }

    local moduleHost = {
        getIdentity = function()
            return {
                id = "StandaloneTest",
                modpack = nil,
            }
        end,
        getMeta = function()
            return {
                name = "Standalone Test",
                shortName = nil,
                tooltip = nil,
            }
        end,
        affectsRunData = function()
            return false
        end,
        getDefinition = function()
            return { id = "StandaloneTest", name = "Standalone Test" }
        end,
        applyOnLoad = function()
            return true, nil
        end,
        read = function(alias)
            if alias == "Enabled" then
                return true
            end
            if alias == "DebugMode" then
                return false
            end
            return nil
        end,
        setEnabled = function()
            return true, nil
        end,
        setDebugMode = noop,
        hasDrawTab = function()
            return true
        end,
        drawTab = function()
            drawCalls = drawCalls + 1
        end,
        commitIfDirty = function()
            return false, "commit boom", false
        end,
    }

    local runtime = lib.standaloneHost(moduleHost)
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(drawCalls, 1)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "Standalone Test session commit failed")
    lu.assertStrContains(Warnings[1], "commit boom")
end

function TestHost:testHostAndAuthorSessionResetToDefaultsDelegateToLibHelper()
    local capturedAuthorSession = nil
    local definition = lib.prepareDefinition({}, {
        id = "ResetHost",
        name = "Reset Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
            { type = "int", alias = "Count", configKey = "Count", default = 2, min = 0, max = 9 },
        },
    })
    local store, session = lib.createStore({
        EnabledFlag = true,
        Count = 7,
    }, definition)
    local host = lib.createModuleHost({
        definition = definition,
        store = store,
        session = session,
        drawTab = function(_, authorSession)
            capturedAuthorSession = authorSession
        end,
    })

    host.drawTab({})

    local changed, count = host.resetToDefaults()
    lu.assertTrue(changed)
    lu.assertEquals(count, 2)
    lu.assertEquals(session.read("EnabledFlag"), false)
    lu.assertEquals(session.read("Count"), 2)

    session.write("EnabledFlag", true)
    session.write("Count", 6)
    local authorChanged, authorCount = capturedAuthorSession.resetToDefaults({
        exclude = { Count = true },
    })
    lu.assertTrue(authorChanged)
    lu.assertEquals(authorCount, 1)
    lu.assertEquals(session.read("EnabledFlag"), false)
    lu.assertEquals(session.read("Count"), 6)
end

function TestHost:testCreateModuleHostSkipsImmediateCoordinatedSyncWhenFrameworkRebuildIsPending()
    local applyCalls = 0
    local packId = "reload-pack"

    lib.lifecycle.registerCoordinator(packId, { ModEnabled = true })
    local definition = lib.prepareDefinition({}, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
    })
    definition._pendingCoordinatorRebuildReason = {
        kind = "structural_definition_changed",
        moduleId = "ReloadHost",
        modpack = packId,
    }

    local store, session = lib.createStore({
        Enabled = true,
        DebugMode = false,
        EnabledFlag = false,
    }, definition)
    local originalApplyOnLoad = lib.lifecycle.applyOnLoad
    lib.lifecycle.applyOnLoad = function(...)
        applyCalls = applyCalls + 1
        return originalApplyOnLoad(...)
    end

    lib.createModuleHost({
        definition = definition,
        store = store,
        session = session,
    })

    lib.lifecycle.applyOnLoad = originalApplyOnLoad
    lib.lifecycle.registerCoordinator(packId, nil)
    lu.assertEquals(applyCalls, 0)
end
