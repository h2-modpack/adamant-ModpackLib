local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')
local DefaultViolationPolicy = dofile('src/core/logging/policies.lua')

TestLogging = {}

local ActiveLines = nil

local function CoreLuaFiles()
    local files = {}
    local isWindows = package.config:sub(1, 1) == "\\"
    local command = isWindows and 'dir /b /s "src\\core\\*.lua"' or 'find src/core -type f -name "*.lua"'
    local handle = assert(io.popen(command))
    for path in handle:lines() do
        files[#files + 1] = string.gsub(path, "\\", "/")
    end
    handle:close()
    table.sort(files)
    return files
end

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
    for _, path in ipairs(CoreLuaFiles()) do
        local handle = assert(io.open(path, "r"))
        local source = handle:read("*a")
        handle:close()
        for id in string.gmatch(source, "[%w_]+%.violate%s*%(%s*[\"']([^\"']+)[\"']") do
            lu.assertNotNil(DefaultViolationPolicy[id], id)
        end
    end
end

function TestLogging.testViolationPolicyHasNoOrphanIds()
    local referenced = {}

    for _, path in ipairs(CoreLuaFiles()) do
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

function TestLogging:testDiagnoseHonorsSubsystemFlag()
    self.harness.logging.diagnose("configBackend", "hidden")
    self.harness.config.Diagnostics = {
        configBackend = true,
    }
    local printed = self.harness.logging.diagnose("configBackend", "visible %s", "summary")

    lu.assertTrue(printed)
    lu.assertEquals(self.lines, { "[lib-diagnostic:configBackend] visible summary" })
end

function TestLogging:testDiagnoseAllowsAllDiagnosticsFlag()
    self.harness.config.Diagnostics = true

    local printed = self.harness.logging.diagnose("storage", "visible")

    lu.assertTrue(printed)
    lu.assertEquals(self.lines, { "[lib-diagnostic:storage] visible" })
end

function TestLogging:testDiagnoseReturnsFalseWhenDisabled()
    local printed = self.harness.logging.diagnose("configBackend", "hidden")

    lu.assertFalse(printed)
    lu.assertEquals(self.lines, {})
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
