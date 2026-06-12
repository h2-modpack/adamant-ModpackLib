local lu = require('luaunit')

TestHudRuntime = {}

function TestHudRuntime:testCreateHudRegistersModpackHashOverlay()
    local overlayOrder = {
        system = 0,
        modpack = 100,
        module = 1000,
        debug = 2000,
    }
    local registeredPack = nil
    local registeredScope = nil
    local registeredLine = nil
    local projectedValue = nil
    local registeredOpts = nil
    local refreshCalls = 0

    local overlaySurface = {
        order = overlayOrder,
        define = function(packId, scope, register)
            registeredPack = packId
            registeredScope = scope
            local registrar = {
                createLine = function(name, spec)
                    registeredLine = name
                    registeredOpts = spec
                end,
                onCommit = function(callback)
                    registeredOpts._commit = callback
                end,
            }
            register(registrar)
            registeredOpts._commit({
                setLine = function(_, value)
                    projectedValue = value
                end,
                refresh = function()
                    refreshCalls = refreshCalls + 1
                end,
            }, {})
            return true
        end,
    }

    local theme = ModpackTestApi.createTheme()
    local config = { ModEnabled = true }
    local hash = {
        GetConfigHash = function()
            return "hash", "fingerprint"
        end,
        ApplyConfigHash = function()
            return true
        end,
    }

    local hud = ModpackTestApi.createHud("test-pack", 1, hash, theme, config, false, overlaySurface)
    hud.install()
    hud.setModMarker(false)

    lu.assertEquals(registeredPack, "test-pack")
    lu.assertEquals(registeredScope, "hud")
    lu.assertEquals(registeredLine, "hash")
    lu.assertEquals(registeredOpts.region, "middleRightStack")
    lu.assertEquals(registeredOpts.order, overlayOrder.modpack + 1)
    lu.assertEquals(projectedValue, "")
    lu.assertFalse(registeredOpts.visible())
    lu.assertEquals(refreshCalls, 2)
end

function TestHudRuntime:testCreateHudInstallClearsModpackHashOverlayWhenHidden()
    local registeredPack = nil
    local registeredScope = nil
    local createLineCalls = 0
    local commitCalls = 0

    local overlaySurface = {
        order = {
            system = 0,
            modpack = 100,
        },
        define = function(packId, scope, register)
            registeredPack = packId
            registeredScope = scope
            register({
                createLine = function()
                    createLineCalls = createLineCalls + 1
                end,
                onCommit = function()
                    commitCalls = commitCalls + 1
                end,
            })
            return true
        end,
    }

    local hud = ModpackTestApi.createHud("test-pack", 1, {
        GetConfigHash = function()
            return "hash", "fingerprint"
        end,
        ApplyConfigHash = function()
            return true
        end,
    }, ModpackTestApi.createTheme(), { ModEnabled = true }, true, overlaySurface)

    hud.install()

    lu.assertEquals(registeredPack, "test-pack")
    lu.assertEquals(registeredScope, "hud")
    lu.assertEquals(createLineCalls, 0)
    lu.assertEquals(commitCalls, 0)
end
