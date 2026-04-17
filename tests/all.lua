-- =============================================================================
-- Run all Lib tests
-- =============================================================================
-- Usage: lua tests/all.lua (from the adamant-modpack-Lib directory)

require('tests/TestUtils')
require('tests/TestBackupSystem')
require('tests/TestDefinitionLifecycle')
require('tests/TestDefinitionContract')
require('tests/TestStorageValidation')
require('tests/TestUiState')
require('tests/TestIsEnabled')
require('tests/TestDataDefaults')

local lu = require('luaunit')
os.exit(lu.LuaUnit.run())
