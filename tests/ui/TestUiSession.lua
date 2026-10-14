local lu = require("luaunit")
local createLibHarness = require("tests/harness/create_lib_harness")
local fakeEngine = require("tests/harness/fake_engine")

TestUiSession = {}

local function createOverlaySurface()
    local surface = { suppressed = 0, released = 0 }
    function surface.suppressForUi()
        surface.suppressed = surface.suppressed + 1
        return {
            release = function()
                surface.released = surface.released + 1
            end,
        }
    end
    return surface
end

function TestUiSession:setUp()
    self.h = createLibHarness()
    self.uiSession = self.h.imports["core/ui/session.lua"]
    self.setupCalls = 0
    self.setupRunData = function()
        self.setupCalls = self.setupCalls + 1
    end
end

function TestUiSession:testFlushRunsSetupRunDataOnlyWhenDirty()
    local session = self.uiSession.create(self.setupRunData, createOverlaySurface())

    session.flushRunData()
    lu.assertEquals(self.setupCalls, 0)

    session.markRunDataDirty()
    session.markRunDataDirty()
    session.flushRunData()
    session.flushRunData()
    lu.assertEquals(self.setupCalls, 1)
end

function TestUiSession:testSuppressionTokenIsHeldOnceAndReleasedOnce()
    local surface = createOverlaySurface()
    local session = self.uiSession.create(self.setupRunData, surface)

    session.suppressOverlays()
    session.suppressOverlays()
    lu.assertEquals(surface.suppressed, 1)

    session.releaseOverlays()
    session.releaseOverlays()
    lu.assertEquals(surface.released, 1)

    session.suppressOverlays()
    lu.assertEquals(surface.suppressed, 2)
end

function TestUiSession:testTrackGuiCloseFiresOnlyOnOpenToClosedEdge()
    local closes = 0
    local function onClosed()
        closes = closes + 1
    end
    local state = { wasGuiOpen = false }

    self.uiSession.trackGuiClose(state, false, onClosed)
    self.uiSession.trackGuiClose(state, true, onClosed)
    lu.assertEquals(closes, 0)

    self.uiSession.trackGuiClose(state, false, onClosed)
    self.uiSession.trackGuiClose(state, false, onClosed)
    lu.assertEquals(closes, 1)
    lu.assertFalse(state.wasGuiOpen)
end

function TestUiSession.testFallbackGuiCloseWatcherLateReadsAnchoredHandler()
    local guiOpen = true
    local callbacks = fakeEngine.createCallbacks()
    local h = createLibHarness({
        callbacks = callbacks,
        rom = {
            gui = {
                is_open = function()
                    return guiOpen
                end,
            },
        },
    })
    local fallbackRegistry = h.runtime.registry.fallback
    -- The fallback GUI-close watcher and the shared hotkey tick.
    lu.assertEquals(#callbacks.alwaysDraw, 2)

    local closes = 0
    fallbackRegistry.handleGuiClosed = function()
        closes = closes + 1
    end

    fakeEngine.runAlwaysDraw(callbacks)
    guiOpen = false
    fakeEngine.runAlwaysDraw(callbacks)
    fakeEngine.runAlwaysDraw(callbacks)

    lu.assertEquals(closes, 1)
    lu.assertFalse(fallbackRegistry.wasGuiOpen)
end
