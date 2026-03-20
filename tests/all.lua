-- =============================================================================
-- Run all Lib tests
-- =============================================================================
-- Usage: lua tests/all.lua (from the adamant-modpack-Lib directory)

require('tests/TestUtils')
require('tests/TestPathHelpers')
require('tests/TestFieldTypes')
require('tests/TestValidation')
require('tests/TestBackupSystem')
require('tests/TestSpecialState')
require('tests/TestIsEnabled')

local lu = require('luaunit')
os.exit(lu.LuaUnit.run())
