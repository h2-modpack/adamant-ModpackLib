local lu = require('luaunit')

TestIsEnabled = {}

function TestIsEnabled:testEnabledWithoutCore()
    rom.mods['adamant-Modpack_Core'] = nil
    lu.assertTrue(lib.isEnabled({ Enabled = true }))
end

function TestIsEnabled:testDisabledWithoutCore()
    rom.mods['adamant-Modpack_Core'] = nil
    lu.assertFalse(lib.isEnabled({ Enabled = false }))
end

function TestIsEnabled:testEnabledWithCoreEnabled()
    rom.mods['adamant-Modpack_Core'] = { config = { ModEnabled = true } }
    lu.assertTrue(lib.isEnabled({ Enabled = true }))
end

function TestIsEnabled:testDisabledWithCoreEnabled()
    rom.mods['adamant-Modpack_Core'] = { config = { ModEnabled = true } }
    lu.assertFalse(lib.isEnabled({ Enabled = false }))
end

function TestIsEnabled:testEnabledWithCoreDisabled()
    rom.mods['adamant-Modpack_Core'] = { config = { ModEnabled = false } }
    lu.assertFalse(lib.isEnabled({ Enabled = true }))
end

function TestIsEnabled:testDisabledWithCoreDisabled()
    rom.mods['adamant-Modpack_Core'] = { config = { ModEnabled = false } }
    lu.assertFalse(lib.isEnabled({ Enabled = false }))
end
