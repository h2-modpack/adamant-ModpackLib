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
    authorHost.integrations.provide(id, {
        providerId = providerId,
        methods = createMethods(api),
    })
    local ok, err = authorHost.activate()
    lu.assertTrue(ok, tostring(err))
    return authorHost
end

local function poll(test, ...)
    if not test.consumerHost then
        local _, authorHost = createIntegrationHost(test.harness, "integration-consumer")
        test.consumerHost = authorHost
    end
    return test.consumerHost.integrations.poll(...)
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
    lu.assertNil(self.integrations.provideForHost)
    lu.assertNil(self.integrations.pollForHost)
end

function TestIntegrations:testAuthorHostProvideInstallsProviderOnActivation()
    activateProvider(self, "integration-register-host", "test.example", "ProviderA", {
        value = function()
            return "registered"
        end,
    })

    local result, providerId = poll(self, "test.example", "value", "fallback")

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

function TestIntegrations:testAuthorHostProvideReplacesSameProviderBeforeActivation()
    local _, authorHost = createIntegrationHost(self.harness, "integration-replace-provider")
    authorHost.integrations.provide("test.example", {
        providerId = "ProviderA",
        methods = createMethods({
            value = function()
                return "first"
            end,
        }),
    })
    authorHost.integrations.provide("test.example", {
        providerId = "ProviderA",
        methods = createMethods({
            value = function()
                return "second"
            end,
        }),
    })

    local ok, err = authorHost.activate()
    lu.assertTrue(ok, tostring(err))

    local result, providerId = poll(self, "test.example", "value", "fallback")
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
    authorHost.integrations.provide(id, {
        providerId = providerId,
        methods = createMethods({
            value = function()
                return "replacement"
            end,
        }),
    })

    local receipt = self.integrations.installForHost(host)
    lu.assertEquals(poll(self, id, "value", "fallback"), "previous")

    local ok, err = receipt.commit()
    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(poll(self, id, "value", "fallback"), "replacement")

    ok, err = receipt.dispose()
    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(poll(self, id, "value", "fallback"), "previous")
end

function TestIntegrations:testAuthorHostProvideRejectsAfterActivation()
    local _, authorHost = createIntegrationHost(self.harness, "integration-facade-activated")
    local ok, err = authorHost.activate()
    lu.assertTrue(ok, tostring(err))

    lu.assertErrorMsgContains("cannot provide after activation begins", function()
        authorHost.integrations.provide("test.activated", {
            providerId = "ActivatedProvider",
            methods = {},
        })
    end)
    lu.assertErrorMsgContains("cannot listen after activation begins", function()
        authorHost.integrations.listen("test.activated", "changed", function() end)
    end)
end

function TestIntegrations:testAuthorHostProvideValidatesRegistrationShape()
    local _, authorHost = createIntegrationHost(self.harness, "integration-facade-invalid")

    lu.assertErrorMsgContains("opts must be a table", function()
        authorHost.integrations.provide("test.invalid")
    end)
    lu.assertErrorMsgContains("providerId must be a non-empty string", function()
        authorHost.integrations.provide("test.invalid", {
            providerId = "",
            methods = {},
        })
    end)
    lu.assertErrorMsgContains("methods must be a table", function()
        authorHost.integrations.provide("test.invalid", {
            providerId = "InvalidProvider",
        })
    end)
    lu.assertErrorMsgContains("reads must be an array", function()
        authorHost.integrations.provide("test.invalid", {
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
    lu.assertErrorMsgContains("events must be a map", function()
        authorHost.integrations.provide("test.invalid", {
            providerId = "InvalidProvider",
            methods = {},
            events = "changed",
        })
    end)
    lu.assertErrorMsgContains("event 'changed' must be declared as true", function()
        authorHost.integrations.provide("test.invalid", {
            providerId = "InvalidProvider",
            methods = {},
            events = {
                changed = false,
            },
        })
    end)
    lu.assertErrorMsgContains("event 'providerChanged' is reserved by Lib", function()
        authorHost.integrations.provide("test.invalid", {
            providerId = "InvalidProvider",
            methods = {},
            events = {
                providerChanged = true,
            },
        })
    end)
    lu.assertErrorMsgContains("callback must be a function", function()
        authorHost.integrations.listen("test.invalid", "changed", true)
    end)
end

function TestIntegrations:testPollCallsMostRecentProviderMethod()
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

    local result, providerId = poll(self, "test.example", "value", "fallback", "x")

    lu.assertEquals(result, "second:x")
    lu.assertEquals(providerId, "ProviderB")
end

function TestIntegrations:testPollSkipsDisabledProviders()
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
    disabledHost.integrations.provide("test.enabled-provider", {
        providerId = "DisabledProvider",
        methods = createMethods({
            value = function()
                return "disabled"
            end,
        }),
    })
    local ok, err = disabledHost.activate()
    lu.assertTrue(ok, tostring(err))

    local result, providerId = poll(self, "test.enabled-provider", "value", "fallback")

    lu.assertEquals(result, "enabled")
    lu.assertEquals(providerId, "EnabledProvider")
end

function TestIntegrations:testEmitDeliversDeclaredEventToActiveListeners()
    local received = {}
    local _, listenerHost = createIntegrationHost(self.harness, "integration-listener")
    listenerHost.integrations.listen("test.events", "changed", function(payload, providerId)
        received[#received + 1] = {
            payload = payload,
            providerId = providerId,
        }
    end)
    local ok, err = listenerHost.activate()
    lu.assertTrue(ok, tostring(err))

    local _, providerHost = createIntegrationHost(self.harness, "integration-event-provider")
    providerHost.integrations.provide("test.events", {
        providerId = "EventProvider",
        methods = createMethods({}),
        events = {
            changed = true,
        },
    })
    ok, err = providerHost.activate()
    lu.assertTrue(ok, tostring(err))

    local emitted, delivered = providerHost.integrations.emit("test.events", "changed", { value = 7 })

    lu.assertTrue(emitted)
    lu.assertEquals(delivered, 1)
    lu.assertEquals(received, {
        {
            payload = { value = 7 },
            providerId = "EventProvider",
        },
    })
end

function TestIntegrations:testEmitReturnsFalseWhenProviderIsDisabled()
    local received = false
    local _, listenerHost = createIntegrationHost(self.harness, "integration-disabled-provider-listener")
    listenerHost.integrations.listen("test.disabled-provider", "changed", function()
        received = true
    end)
    local ok, err = listenerHost.activate()
    lu.assertTrue(ok, tostring(err))

    local _, providerHost = createIntegrationHost(self.harness, "integration-disabled-event-provider", {
        config = {
            Enabled = false,
        },
    })
    providerHost.integrations.provide("test.disabled-provider", {
        providerId = "DisabledEventProvider",
        methods = createMethods({}),
        events = {
            changed = true,
        },
    })
    ok, err = providerHost.activate()
    lu.assertTrue(ok, tostring(err))

    local emitted, reason = providerHost.integrations.emit("test.disabled-provider", "changed", {})

    lu.assertFalse(emitted)
    lu.assertEquals(reason, "no enabled provider")
    lu.assertFalse(received)
end

function TestIntegrations:testEmitRejectsReservedProviderChangedEvent()
    local _, providerHost = createIntegrationHost(self.harness, "integration-reserved-event-provider")
    providerHost.integrations.provide("test.reserved-event", {
        providerId = "EventProvider",
        methods = createMethods({}),
        events = {
            changed = true,
        },
    })
    local ok, err = providerHost.activate()
    lu.assertTrue(ok, tostring(err))

    lu.assertErrorMsgContains("event 'providerChanged' is reserved by Lib", function()
        providerHost.integrations.emit("test.reserved-event", "providerChanged", {})
    end)
end

function TestIntegrations:testEnableDisableEmitsProviderChangedAfterEffectiveTransition()
    local observed = {}
    local _, listenerHost = createIntegrationHost(self.harness, "integration-provider-changed-listener")
    listenerHost.integrations.listen("test.provider-changed", "providerChanged", function(payload, providerId)
        observed[#observed + 1] = {
            enabled = payload.enabled,
            providerId = providerId,
            value = listenerHost.integrations.poll("test.provider-changed", "value", "fallback"),
        }
    end)
    local ok, err = listenerHost.activate()
    lu.assertTrue(ok, tostring(err))

    local providerFullHost, providerHost = createIntegrationHost(self.harness, "integration-provider-changed-provider")
    providerHost.integrations.provide("test.provider-changed", {
        providerId = "ChangedProvider",
        methods = createMethods({
            value = function()
                return "enabled"
            end,
        }),
    })
    ok, err = providerHost.activate()
    lu.assertTrue(ok, tostring(err))

    ok, err = providerFullHost.setEnabled(false)
    lu.assertTrue(ok, tostring(err))
    ok, err = providerFullHost.setEnabled(true)
    lu.assertTrue(ok, tostring(err))

    lu.assertEquals(observed, {
        {
            enabled = false,
            providerId = "ChangedProvider",
            value = "fallback",
        },
        {
            enabled = true,
            providerId = "ChangedProvider",
            value = "enabled",
        },
    })
end

function TestIntegrations:testEmitSkipsDisabledListeners()
    local received = false
    local _, listenerHost = createIntegrationHost(self.harness, "integration-disabled-listener", {
        config = {
            Enabled = false,
        },
    })
    listenerHost.integrations.listen("test.disabled-listener", "changed", function()
        received = true
    end)
    local ok, err = listenerHost.activate()
    lu.assertTrue(ok, tostring(err))

    local _, providerHost = createIntegrationHost(self.harness, "integration-enabled-event-provider")
    providerHost.integrations.provide("test.disabled-listener", {
        providerId = "EventProvider",
        methods = createMethods({}),
        events = {
            changed = true,
        },
    })
    ok, err = providerHost.activate()
    lu.assertTrue(ok, tostring(err))

    local emitted, delivered = providerHost.integrations.emit("test.disabled-listener", "changed", {})

    lu.assertTrue(emitted)
    lu.assertEquals(delivered, 0)
    lu.assertFalse(received)
end

function TestIntegrations:testEmitRejectsUndeclaredProviderEvent()
    local _, providerHost = createIntegrationHost(self.harness, "integration-undeclared-event-provider")
    providerHost.integrations.provide("test.undeclared-event", {
        providerId = "EventProvider",
        methods = createMethods({}),
        events = {
            changed = true,
        },
    })
    local ok, err = providerHost.activate()
    lu.assertTrue(ok, tostring(err))

    lu.assertErrorMsgContains("integrations.undeclared_event", function()
        providerHost.integrations.emit("test.undeclared-event", "missing", {})
    end)
end

function TestIntegrations:testEmitQueuesNestedEventsUntilCurrentFanoutCompletes()
    local order = {}
    local _, providerHost = createIntegrationHost(self.harness, "integration-nested-event-provider")
    providerHost.integrations.provide("test.nested-events", {
        providerId = "NestedProvider",
        methods = createMethods({}),
        events = {
            first = true,
            second = true,
        },
    })
    local ok, err = providerHost.activate()
    lu.assertTrue(ok, tostring(err))

    local _, listenerHost = createIntegrationHost(self.harness, "integration-nested-listener")
    listenerHost.integrations.listen("test.nested-events", "first", function()
        order[#order + 1] = "first-a"
        providerHost.integrations.emit("test.nested-events", "second", {})
    end)
    listenerHost.integrations.listen("test.nested-events", "first", function()
        order[#order + 1] = "first-b"
    end)
    listenerHost.integrations.listen("test.nested-events", "second", function()
        order[#order + 1] = "second"
    end)
    ok, err = listenerHost.activate()
    lu.assertTrue(ok, tostring(err))

    local emitted, delivered = providerHost.integrations.emit("test.nested-events", "first", {})

    lu.assertTrue(emitted)
    lu.assertEquals(delivered, 3)
    lu.assertEquals(order, {
        "first-a",
        "first-b",
        "second",
    })
end

function TestIntegrations:testListenerFailureLogsAndContinuesFanout()
    local warnings = {}
    self.harness.env.print = function(message)
        warnings[#warnings + 1] = message
    end
    local reached = false
    local _, listenerHost = createIntegrationHost(self.harness, "integration-failing-listener")
    listenerHost.integrations.listen("test.listener-failure", "changed", function()
        error("listener boom")
    end)
    listenerHost.integrations.listen("test.listener-failure", "changed", function()
        reached = true
    end)
    local ok, err = listenerHost.activate()
    lu.assertTrue(ok, tostring(err))

    local _, providerHost = createIntegrationHost(self.harness, "integration-listener-failure-provider")
    providerHost.integrations.provide("test.listener-failure", {
        providerId = "EventProvider",
        methods = createMethods({}),
        events = {
            changed = true,
        },
    })
    ok, err = providerHost.activate()
    lu.assertTrue(ok, tostring(err))

    local emitted, delivered = providerHost.integrations.emit("test.listener-failure", "changed", {})

    lu.assertTrue(emitted)
    lu.assertEquals(delivered, 2)
    lu.assertTrue(reached)
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "integrations.listener_failed")
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
    authorHost.integrations.provide("test.scoped", {
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

    local result = poll(self, "test.scoped", "value", "fallback")

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
    authorHost.integrations.provide("test.scoped", {
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

    local result = poll(self, "test.scoped", "value", "fallback")

    lu.assertEquals(result, "fallback")
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "integrations.undeclared_read")
end

function TestIntegrations:testPollUsesCurrentProviderAfterReload()
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

    lu.assertEquals(poll(self, "test.example", "value", "fallback"), "second")
end

function TestIntegrations:testPollReturnsFallbackForMissingProviderOrMethod()
    lu.assertEquals(poll(self, "test.missing", "value", "fallback"), "fallback")

    activateProvider(self, "integration-missing-method", "test.example", "ProviderA", {})

    local result, providerId = poll(self, "test.example", "value", "fallback")

    lu.assertEquals(result, "fallback")
    lu.assertEquals(providerId, "ProviderA")
end

function TestIntegrations:testPollReturnsFallbackWhenProviderMethodFails()
    local warnings = {}
    self.harness.env.print = function(message)
        warnings[#warnings + 1] = message
    end
    activateProvider(self, "integration-failing-provider", "test.example", "ProviderA", {
        value = function()
            error("boom")
        end,
    })

    local result, providerId = poll(self, "test.example", "value", "fallback")

    lu.assertEquals(result, "fallback")
    lu.assertEquals(providerId, "ProviderA")
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "test.example.value provider 'ProviderA' failed")
end
