local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')
local DefaultViolationPolicy = dofile('src/core/logging/policies.lua')

TestLogging = {}

local ActiveLines = nil

local function CaptureHarnessPrint(harness)
    local previousPrint = harness.env.print
    if ActiveLines ~= nil then
        harness.env.print = function(msg)
            ActiveLines[#ActiveLines + 1] = msg
        end
    end
    return function()
        harness.env.print = previousPrint
    end
end

local function WithLoggingPolicy(policy, callback)
    local harness = createLibHarness({
        importOverrides = {
            ["core/logging/policies.lua"] = policy,
        },
    })
    local restorePrint = CaptureHarnessPrint(harness)
    local ok, err = pcall(callback, harness.logging, harness)
    restorePrint()
    if not ok then
        error(err, 0)
    end
end

function TestLogging:setUp()
    self.harness = createLibHarness()
    self.lines = {}
    ActiveLines = self.lines
    self.restorePrint = CaptureHarnessPrint(self.harness)
end

function TestLogging:tearDown()
    self.restorePrint()
    self.restorePrint = nil
    ActiveLines = nil
    self.harness = nil
end

function TestLogging:testViolationWarnUsesPolicyId()
    WithLoggingPolicy({
        ["test.warn"] = {
            severity = "warn",
            description = "Test warning policy.",
        },
    }, function(activeLogging)
        local severity, message = activeLogging.violate("test.warn", "hello %s", "world")

        lu.assertEquals(severity, "warn")
        lu.assertEquals(message, "[lib] test.warn: hello world")
        lu.assertEquals(self.lines, { "[lib] test.warn: hello world" })
    end)
end

function TestLogging.testViolationPolicyCarriesDescriptions()
    local policy = DefaultViolationPolicy["storage.hash_requires_persist"]

    lu.assertEquals(policy.severity, "error")
    lu.assertStrContains(policy.description, "persisted")
end

function TestLogging.testViolationPolicyMatchesSourceCallSites()
    local files = {
        "src/core/module_bootstrap/definition.lua",
        "src/core/module_bootstrap/ui/phase.lua",
        "src/core/module_bootstrap/ui/phase_gate.lua",
        "src/core/cache/00_init.lua",
        "src/core/cache/adapters/data_cache.lua",
        "src/core/cache/current_run_cache.lua",
        "src/core/controls/00_init.lua",
        "src/core/controls/compiler.lua",
        "src/core/controls/declarations.lua",
        "src/core/controls/draw_controls.lua",
        "src/core/controls/refs.lua",
        "src/core/hooks/00_init.lua",
        "src/core/hooks/adapters/module_install.lua",
        "src/core/hooks/declarations.lua",
        "src/core/hooks/dispatchers.lua",
        "src/core/hooks/host_install.lua",
        "src/core/hooks/adapters/system_declarations.lua",
        "src/core/hooks/modutil_registry.lua",
        "src/core/module_bootstrap/managed_module.lua",
        "src/core/module_bootstrap/managed_module_activation.lua",
        "src/core/module_bootstrap/managed_module_lifecycle.lua",
        "src/core/shared/00_init.lua",
        "src/core/shared/adapters/data_shared.lua",
        "src/core/shared/adapters/module_install.lua",
        "src/core/shared/events/events.lua",
        "src/core/shared/events/registrations.lua",
        "src/core/shared/data.lua",
        "src/core/lib_bootstrap/framework_runtime.lua",
        "src/core/lib_bootstrap/system_scope.lua",
        "src/core/coordinator/coordinator.lua",
        "src/core/game_deps/game_deps.lua",
        "src/core/module_bootstrap/module.lua",
        "src/core/overlays/00_init.lua",
        "src/core/overlays/adapters/framework_overlays.lua",
        "src/core/overlays/adapters/module_install.lua",
        "src/core/overlays/adapters/system_retained.lua",
        "src/core/overlays/renderer.lua",
        "src/core/overlays/retained_dispatch.lua",
        "src/core/overlays/retained.lua",
        "src/core/overlays/registry.lua",
        "src/core/mutations/00_init.lua",
        "src/core/mutations/adapters/module_lifecycle.lua",
        "src/core/mutations/lifecycle.lua",
        "src/core/fallback/fallback_ui.lua",
        "src/core/module_state/00_init.lua",
        "src/core/module_state/actions/action_buffer.lua",
        "src/core/module_state/actions/ui_actions.lua",
        "src/core/logging/logging.lua",
        "src/core/helpers/values.lua",
        "src/core/module_state/staged/staged_state.lua",
        "src/core/module_state/persistent/persistent_state.lua",
        "src/core/storage/00_init.lua",
        "src/core/storage/alias_access.lua",
        "src/core/storage/schema.lua",
        "src/core/storage/storage_field.lua",
        "src/core/storage/packed.lua",
        "src/core/storage/table.lua",
        "src/core/storage/types.lua",
        "src/core/module_state/persistent/store.lua",
        "src/core/widgets/00_init.lua",
        "src/core/widgets/ui_draw.lua",
        "src/core/widgets/widget_helpers.lua",
        "src/core/widgets/buttons.lua",
    }

    for _, path in ipairs(files) do
        local handle = assert(io.open(path, "r"))
        local source = handle:read("*a")
        handle:close()
        for id in string.gmatch(source, "[%w_]+%.violate%s*%(%s*[\"']([^\"']+)[\"']") do
            lu.assertNotNil(DefaultViolationPolicy[id], id)
        end
    end
end

function TestLogging.testViolationPolicyHasNoOrphanIds()
    local files = {
        "src/core/module_bootstrap/definition.lua",
        "src/core/module_bootstrap/ui/phase.lua",
        "src/core/module_bootstrap/ui/phase_gate.lua",
        "src/core/cache/00_init.lua",
        "src/core/cache/adapters/data_cache.lua",
        "src/core/cache/current_run_cache.lua",
        "src/core/controls/00_init.lua",
        "src/core/controls/compiler.lua",
        "src/core/controls/declarations.lua",
        "src/core/controls/draw_controls.lua",
        "src/core/controls/refs.lua",
        "src/core/hooks/00_init.lua",
        "src/core/hooks/adapters/module_install.lua",
        "src/core/hooks/declarations.lua",
        "src/core/hooks/dispatchers.lua",
        "src/core/hooks/host_install.lua",
        "src/core/hooks/adapters/system_declarations.lua",
        "src/core/hooks/modutil_registry.lua",
        "src/core/module_bootstrap/managed_module.lua",
        "src/core/module_bootstrap/managed_module_activation.lua",
        "src/core/module_bootstrap/managed_module_lifecycle.lua",
        "src/core/shared/00_init.lua",
        "src/core/shared/adapters/data_shared.lua",
        "src/core/shared/adapters/module_install.lua",
        "src/core/shared/events/events.lua",
        "src/core/shared/events/registrations.lua",
        "src/core/shared/data.lua",
        "src/core/lib_bootstrap/framework_runtime.lua",
        "src/core/lib_bootstrap/system_scope.lua",
        "src/core/coordinator/coordinator.lua",
        "src/core/game_deps/game_deps.lua",
        "src/core/module_bootstrap/module.lua",
        "src/core/overlays/00_init.lua",
        "src/core/overlays/adapters/framework_overlays.lua",
        "src/core/overlays/adapters/module_install.lua",
        "src/core/overlays/adapters/system_retained.lua",
        "src/core/overlays/renderer.lua",
        "src/core/overlays/retained_dispatch.lua",
        "src/core/overlays/retained.lua",
        "src/core/overlays/registry.lua",
        "src/core/mutations/00_init.lua",
        "src/core/mutations/adapters/module_lifecycle.lua",
        "src/core/mutations/lifecycle.lua",
        "src/core/fallback/fallback_ui.lua",
        "src/core/module_state/00_init.lua",
        "src/core/module_state/actions/action_buffer.lua",
        "src/core/module_state/actions/ui_actions.lua",
        "src/core/logging/logging.lua",
        "src/core/helpers/values.lua",
        "src/core/module_state/staged/staged_state.lua",
        "src/core/module_state/persistent/persistent_state.lua",
        "src/core/storage/00_init.lua",
        "src/core/storage/alias_access.lua",
        "src/core/storage/schema.lua",
        "src/core/storage/storage_field.lua",
        "src/core/storage/packed.lua",
        "src/core/storage/table.lua",
        "src/core/storage/types.lua",
        "src/core/module_state/persistent/store.lua",
        "src/core/widgets/00_init.lua",
        "src/core/widgets/ui_draw.lua",
        "src/core/widgets/widget_helpers.lua",
        "src/core/widgets/buttons.lua",
    }
    local referenced = {}

    for _, path in ipairs(files) do
        local handle = assert(io.open(path, "r"))
        local source = handle:read("*a")
        handle:close()
        for id in string.gmatch(source, "[%w_]+%.violate%s*%(%s*[\"']([^\"']+)[\"']") do
            referenced[id] = true
        end
    end

    for id in pairs(DefaultViolationPolicy) do
        lu.assertTrue(referenced[id], id)
    end
end

function TestLogging:testViolationDebugHonorsLibDebugMode()
    WithLoggingPolicy({
        ["test.debug"] = {
            severity = "debug",
            description = "Test debug policy.",
        },
    }, function(activeLogging, harness)
        activeLogging.violate("test.debug", "hidden")
        harness.config.DebugMode = true
        activeLogging.violate("test.debug", "visible")
    end)

    lu.assertEquals(self.lines, { "[lib] test.debug: visible" })
end

function TestLogging:testViolationIgnoreReturnsWithoutPrinting()
    WithLoggingPolicy({
        ["test.ignore"] = {
            severity = "ignore",
            description = "Test ignored policy.",
        },
    }, function(activeLogging)
        local severity, message = activeLogging.violate("test.ignore", "ignored")

        lu.assertEquals(severity, "ignore")
        lu.assertEquals(message, "[lib] test.ignore: ignored")
        lu.assertEquals(self.lines, {})
    end)
end

function TestLogging.testViolationErrorRaises()
    WithLoggingPolicy({
        ["test.error"] = {
            severity = "error",
            description = "Test error policy.",
        },
    }, function(activeLogging)
        local ok, err = pcall(function()
            activeLogging.violate("test.error", "broken")
        end)

        lu.assertFalse(ok)
        lu.assertStrContains(err, "[lib] test.error: broken")
        lu.assertStrContains(err, "stack traceback")
    end)
end

function TestLogging.testViolationRejectsInvalidSeverity()
    WithLoggingPolicy({
        ["test.invalid"] = {
            severity = "trace",
            description = "Test invalid policy.",
        },
    }, function(activeLogging)
        lu.assertErrorMsgContains("violation.invalid_severity", function()
            activeLogging.violate("test.invalid", "broken")
        end)
    end)
end

function TestLogging:testViolationRejectsUnknownId()
    lu.assertErrorMsgContains("violation.unknown_id", function()
        self.harness.logging.violate("test.missing", "broken")
    end)
end
