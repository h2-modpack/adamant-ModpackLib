-- =============================================================================
-- Run all Lib tests
-- =============================================================================
-- Usage: lua tests/all.lua (from the adamant-modpack-Lib directory)

require('tests/TestUtils')
require('tests/TestBackupSystem')
require('tests/TestDefinitionLifecycle')
require('tests/TestDefinitionContract')
require('tests/TestPrepareDefinition')
require('tests/TestStorageValidation')
require('tests/TestSession')
require('tests/TestIsEnabled')
require('tests/TestDataDefaults')
require('tests/TestIntegrations')
require('tests/TestHooks')
require('tests/TestHost')
require('tests/TestWidgets')

local lu = require('luaunit')
os.exit(lu.LuaUnit.run())
