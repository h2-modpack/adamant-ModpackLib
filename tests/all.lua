-- =============================================================================
-- Run all Lib tests
-- =============================================================================
-- Usage: lua tests/all.lua (from the adamant-modpack-Lib directory)

require('tests/bootstrap/TestMainBoot')
require('tests/bootstrap/TestLogging')
require('tests/bootstrap/TestValues')
require('tests/bootstrap/TestGameDeps')
require('tests/bootstrap/TestSystemScope')

require('tests/storage/TestStorageValidation')
require('tests/storage/TestHashing')

require('tests/module_state/TestModuleState_DataDefaults')
require('tests/module_state/TestModuleState_PersistentState')
require('tests/module_state/TestModuleState_StagedState')

require('tests/cache/TestCache')
require('tests/controls/TestControls')
require('tests/coordinator/TestCoordinator')
require('tests/shared/TestShared')
require('tests/hooks/TestHooks')
require('tests/overlays/TestOverlays')
require('tests/overlays/TestOverlays_Retained')
require('tests/mutations/TestMutation_BackupSystem')
require('tests/mutations/TestMutation_DefinitionLifecycle')
require('tests/mutations/TestMutation')
require('tests/module/TestManagedModule')
require('tests/module/TestModuleDefinitionContract')
require('tests/module/TestCreateModule')
require('tests/module/TestManagedModule_PrepareDefinition')
require('tests/module/TestManagedModule_IsEnabled')
require('tests/fallback/TestFallbackUi')
require('tests/widgets/TestWidgets')
require('tests/widgets/TestWidgets_Nav')

require('tests/modpack/TestUtils')
require('tests/modpack/TestModuleRegistry')
require('tests/modpack/TestConfigHash')
require('tests/modpack/TestAuditProfiles')
require('tests/modpack/TestPackBootstrap')
require('tests/modpack/TestHudRuntime')
require('tests/modpack/TestUiRuntime')
require('tests/modpack/TestUiWindow')

local lu = require('luaunit')
os.exit(lu.LuaUnit.run())
