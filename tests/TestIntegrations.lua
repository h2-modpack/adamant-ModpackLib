local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestIntegrations = {}

local function createIntegrationHost(harness, pluginGuid, opts)
    opts = opts or {}
    local config = opts.config or {}
    if config.Enabled == nil then
        config.Enabled = true
    end
    local definition = harness.moduleHost.prepareDefinition({}, {
        id = "IntegrationHost",
        name = "Integration Host",
        storage = opts.storage or {},
    })
    local state = harness.moduleState.create(config, definition)
    local host, authorHost = harness.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        persistentState = state.persistentState,
        stagedState = state.stagedState,
        drawTab = function() end,
    })
    return host, authorHost, state
end

local function createMethods(api)
    local methods = {}
    for name, handler in pairs(api or {}) do
        methods[name] = {
            handler = function(_, ...)
                return handler(...)
            end,
        }
    end
    return methods
end

local function activateProvider(test, pluginGuid, id, providerId, api)
    local _, authorHost = createIntegrationHost(test.harness, pluginGuid)
    authorHost.integrations.register(id, {
        providerId = providerId,
        methods = createMethods(api),
    })
    local ok, err = authorHost.activate()
    lu.assertTrue(ok, tostring(err))
    return authorHost
end

local function invoke(test, ...)
    if not test.consumerHost then
        local _, authorHost = createIntegrationHost(test.harness, "integration-consumer")
        test.consumerHost = authorHost
    end
    return test.consumerHost.integrations.invoke(...)
end

function TestIntegrations:setUp()
    self.harness = createLibHarness()
    self.consumerHost = nil
    self.integrations = self.harness.integrations
end

function TestIntegrations:testPublicSurfaceIsClosed()
    lu.assertNil(self.harness.public.integrations)
end

function TestIntegrations:testServiceSurfaceOnlyExposesHostInstallation()
    lu.assertEquals(type(self.integrations.installForHost), "function")
    lu.assertNil(self.integrations.registerForHost)
    lu.assertNil(self.integrations.invokeForHost)
end

function TestIntegrations:testAuthorHostRegisterInstallsProviderOnActivation()
    activateProvider(self, "integration-register-host", "test.example", "ProviderA", {
        value = function()
            return "registered"
        end,
    })

    local result, providerId = invoke(self, "test.example", "value", "fallback")

    lu.assertEquals(result, "registered")
    lu.assertEquals(providerId, "ProviderA")
end

function TestIntegrations:testRegistryStoresLifecycleOwnerIdAndInstallToken()
    local pluginGuid = "integration-owner-id"
    local integrationId = "test.owner.identity"
    local providerId = "OwnerProvider"
    activateProvider(self, pluginGuid, integrationId, providerId, {
        value = function()
            return "owned"
        end,
    })

    local bucket = self.harness.registry.integrations.providers[integrationId]

    lu.assertEquals(bucket.ownerIds[providerId], pluginGuid)
    lu.assertEquals(type(bucket.ownerTokens[providerId]), "table")
    lu.assertNotEquals(bucket.ownerTokens[providerId], self.harness.moduleHost.getLiveHost(pluginGuid))
    lu.assertNil(bucket.owners)
end

function TestIntegrations:testAuthorHostRegisterReplacesSameProviderBeforeActivation()
    local _, authorHost = createIntegrationHost(self.harness, "integration-replace-provider")
    authorHost.integrations.register("test.example", {
        providerId = "ProviderA",
        methods = createMethods({
            value = function()
                return "first"
            end,
        }),
    })
    authorHost.integrations.register("test.example", {
        providerId = "ProviderA",
        methods = createMethods({
            value = function()
                return "second"
            end,
        }),
    })

    local ok, err = authorHost.activate()
    lu.assertTrue(ok, tostring(err))

    local result, providerId = invoke(self, "test.example", "value", "fallback")
    lu.assertEquals(result, "second")
    lu.assertEquals(providerId, "ProviderA")
end

function TestIntegrations:testHostInstallStagesProvidersUntilCommit()
    local id = "test.host.facade"
    local providerId = "FacadeProvider"
    activateProvider(self, "integration-previous-provider", id, providerId, {
        value = function()
            return "previous"
        end,
    })
    local host, authorHost = createIntegrationHost(self.harness, "integration-facade-host")
    authorHost.integrations.register(id, {
        providerId = providerId,
        methods = createMethods({
            value = function()
                return "replacement"
            end,
        }),
    })

    local receipt = self.integrations.installForHost(host)
    lu.assertEquals(invoke(self, id, "value", "fallback"), "previous")

    local ok, err = receipt.commit()
    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(invoke(self, id, "value", "fallback"), "replacement")

    ok, err = receipt.dispose()
    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(invoke(self, id, "value", "fallback"), "previous")
end

function TestIntegrations:testAuthorHostRegisterRejectsAfterActivation()
    local _, authorHost = createIntegrationHost(self.harness, "integration-facade-activated")
    local ok, err = authorHost.activate()
    lu.assertTrue(ok, tostring(err))

    lu.assertErrorMsgContains("cannot register after activation begins", function()
        authorHost.integrations.register("test.activated", {
            providerId = "ActivatedProvider",
            methods = {},
        })
    end)
end

function TestIntegrations:testAuthorHostRegisterValidatesRegistrationShape()
    local _, authorHost = createIntegrationHost(self.harness, "integration-facade-invalid")

    lu.assertErrorMsgContains("opts must be a table", function()
        authorHost.integrations.register("test.invalid")
    end)
    lu.assertErrorMsgContains("providerId must be a non-empty string", function()
        authorHost.integrations.register("test.invalid", {
            providerId = "",
            methods = {},
        })
    end)
    lu.assertErrorMsgContains("methods must be a table", function()
        authorHost.integrations.register("test.invalid", {
            providerId = "InvalidProvider",
        })
    end)
    lu.assertErrorMsgContains("reads must be an array", function()
        authorHost.integrations.register("test.invalid", {
            providerId = "InvalidProvider",
            methods = {
                value = {
                    reads = {
                        Flag = true,
                    },
                    handler = function() end,
                },
            },
        })
    end)
end

function TestIntegrations:testInvokeCallsMostRecentProviderMethod()
    activateProvider(self, "integration-provider-first", "test.example", "ProviderA", {
        value = function()
            return "first"
        end,
    })
    activateProvider(self, "integration-provider-second", "test.example", "ProviderB", {
        value = function(suffix)
            return "second:" .. suffix
        end,
    })

    local result, providerId = invoke(self, "test.example", "value", "fallback", "x")

    lu.assertEquals(result, "second:x")
    lu.assertEquals(providerId, "ProviderB")
end

function TestIntegrations:testInvokeSkipsDisabledProviders()
    activateProvider(self, "integration-provider-enabled", "test.enabled-provider", "EnabledProvider", {
        value = function()
            return "enabled"
        end,
    })
    local _, disabledHost = createIntegrationHost(self.harness, "integration-provider-disabled", {
        config = {
            Enabled = false,
        },
    })
    disabledHost.integrations.register("test.enabled-provider", {
        providerId = "DisabledProvider",
        methods = createMethods({
            value = function()
                return "disabled"
            end,
        }),
    })
    local ok, err = disabledHost.activate()
    lu.assertTrue(ok, tostring(err))

    local result, providerId = invoke(self, "test.enabled-provider", "value", "fallback")

    lu.assertEquals(result, "enabled")
    lu.assertEquals(providerId, "EnabledProvider")
end

function TestIntegrations:testProviderMethodReceivesScopedStagedReads()
    local capturedScope = nil
    local capturedField = nil
    local host, authorHost = createIntegrationHost(self.harness, "integration-scoped-staged-read", {
        config = {
            Enabled = true,
            Flag = false,
        },
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    })
    authorHost.integrations.register("test.scoped", {
        providerId = "ScopedProvider",
        methods = {
            value = {
                reads = { "Flag" },
                handler = function(scope)
                    capturedScope = scope
                    capturedField = scope.get("Flag")
                    return {
                        direct = scope.read("Flag"),
                        field = capturedField:read(),
                    }
                end,
            },
        },
    })
    local ok, err = authorHost.activate()
    lu.assertTrue(ok, tostring(err))
    host.stage("Flag", true)

    local result = invoke(self, "test.scoped", "value", "fallback")

    lu.assertEquals(result, {
        direct = true,
        field = true,
    })
    lu.assertErrorMsgContains("integrations.closed_scope", function()
        capturedScope.read("Flag")
    end)
    lu.assertErrorMsgContains("integrations.closed_scope", function()
        capturedField:read()
    end)
end

function TestIntegrations:testProviderMethodRejectsUndeclaredRead()
    local warnings = {}
    self.harness.env.print = function(message)
        warnings[#warnings + 1] = message
    end
    local _, authorHost = createIntegrationHost(self.harness, "integration-scoped-undeclared-read", {
        config = {
            Enabled = true,
            Flag = false,
        },
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    })
    authorHost.integrations.register("test.scoped", {
        providerId = "ScopedProvider",
        methods = {
            value = {
                handler = function(scope)
                    return scope.read("Flag")
                end,
            },
        },
    })
    local ok, err = authorHost.activate()
    lu.assertTrue(ok, tostring(err))

    local result = invoke(self, "test.scoped", "value", "fallback")

    lu.assertEquals(result, "fallback")
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "integrations.undeclared_read")
end

function TestIntegrations:testInvokeUsesCurrentProviderAfterReload()
    local pluginGuid = "integration-provider-reload"
    activateProvider(self, pluginGuid, "test.example", "ProviderA", {
        value = function()
            return "first"
        end,
    })
    activateProvider(self, pluginGuid, "test.example", "ProviderA", {
        value = function()
            return "second"
        end,
    })

    lu.assertEquals(invoke(self, "test.example", "value", "fallback"), "second")
end

function TestIntegrations:testInvokeReturnsFallbackForMissingProviderOrMethod()
    lu.assertEquals(invoke(self, "test.missing", "value", "fallback"), "fallback")

    activateProvider(self, "integration-missing-method", "test.example", "ProviderA", {})

    local result, providerId = invoke(self, "test.example", "value", "fallback")

    lu.assertEquals(result, "fallback")
    lu.assertEquals(providerId, "ProviderA")
end

function TestIntegrations:testInvokeReturnsFallbackWhenProviderMethodFails()
    local warnings = {}
    self.harness.env.print = function(message)
        warnings[#warnings + 1] = message
    end
    activateProvider(self, "integration-failing-provider", "test.example", "ProviderA", {
        value = function()
            error("boom")
        end,
    })

    local result, providerId = invoke(self, "test.example", "value", "fallback")

    lu.assertEquals(result, "fallback")
    lu.assertEquals(providerId, "ProviderA")
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "test.example.value provider 'ProviderA' failed")
end
