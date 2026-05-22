local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestIntegrations = {}

local function createIntegrationHost(harness, pluginGuid)
    local definition = harness.moduleHost.prepareDefinition({}, {
        id = "IntegrationHost",
        name = "Integration Host",
        storage = {},
    })
    local state = harness.moduleState.create({}, definition)
    local host, authorHost = harness.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        persistentState = state.persistentState,
        stagedState = state.stagedState,
        drawTab = function() end,
    })
    return host, authorHost
end

local function activateProvider(test, pluginGuid, id, providerId, api)
    local _, authorHost = createIntegrationHost(test.harness, pluginGuid)
    authorHost.integrations.register(id, {
        providerId = providerId,
        api = api,
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
        api = {
            value = function()
                return "first"
            end,
        },
    })
    authorHost.integrations.register("test.example", {
        providerId = "ProviderA",
        api = {
            value = function()
                return "second"
            end,
        },
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
        api = {
            value = function()
                return "replacement"
            end,
        },
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
            api = {},
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
            api = {},
        })
    end)
    lu.assertErrorMsgContains("api must be a table", function()
        authorHost.integrations.register("test.invalid", {
            providerId = "InvalidProvider",
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
