-- luacheck: globals TestShared

local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestShared = {}

local function createSharedHost(harness, pluginGuid, opts)
    opts = opts or {}
    local config = opts.config or {}
    if config.Enabled == nil then
        config.Enabled = true
    end
    local definition = harness.moduleHost.prepareDefinition({}, {
        id = opts.id or "SharedHost",
        name = opts.name or "Shared Host",
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

local function activateHost(harness, pluginGuid, opts)
    local host, authorHost, state = createSharedHost(harness, pluginGuid, opts)
    if opts and opts.configureHost then
        opts.configureHost(authorHost, host, state)
    end
    local ok, err = authorHost.activate()
    lu.assertTrue(ok, tostring(err))
    return host, authorHost, state
end

local function activateAndEnableHost(harness, host, pluginGuid)
    lu.assertTrue(host.activate())
    local fullHost = harness.moduleHost.getLiveHost(pluginGuid)
    lu.assertNotNil(fullHost)
    lu.assertTrue(fullHost.setEnabled(true))
    return fullHost
end

local function createSharedModule(harness, pluginGuid, opts)
    opts = opts or {}
    local host, store = harness.public.createModule({
        pluginGuid = pluginGuid,
        config = opts.config or {},
        modpack = "test-pack",
        id = opts.id or ("Shared" .. tostring(pluginGuid):gsub("[^%w_]", "")),
        name = opts.name or pluginGuid,
        drawTab = opts.drawTab or function() end,
    })
    for name, declaration in pairs(opts.shared or {}) do
        if declaration.access == "owner" then
            host.shared.data.owner(name, {
                id = declaration.id,
                default = declaration.default,
            })
        else
            host.shared.data.reader(name, {
                id = declaration.id,
                fallback = declaration.fallback,
            })
        end
    end
    return host, store
end

function TestShared:setUp()
    self.harness = createLibHarness()
    self.shared = self.harness.shared
end

function TestShared:testPublicSurfaceIsClosed()
    lu.assertNil(self.harness.public.shared)
end

function TestShared:testServiceSurfaceExposesInstallAndData()
    lu.assertEquals(type(self.shared.installForHost), "function")
    lu.assertEquals(type(self.shared.data), "table")
    lu.assertNil(self.shared.provideForHost)
    lu.assertNil(self.shared.pollForHost)
    lu.assertNil(self.shared.notifyProviderChangedForHost)
end

function TestShared:testAuthorSurfaceExposesDataAndEvents()
    local _, authorHost = createSharedHost(self.harness, "shared-author-surface")

    lu.assertEquals(type(authorHost.shared.data), "table")
    lu.assertEquals(type(authorHost.shared.data.owner), "function")
    lu.assertEquals(type(authorHost.shared.data.reader), "function")
    lu.assertEquals(type(authorHost.shared.listen), "function")
    lu.assertEquals(type(authorHost.shared.emit), "function")
    lu.assertNil(authorHost.shared.provide)
    lu.assertNil(authorHost.shared.poll)
end

function TestShared:testSharedDataDeclarationsDoNotAffectStructuralFingerprint()
    local owner = {}
    local first, firstAuthorHost = createSharedHost(self.harness, "shared-structural-a", {
        id = "SharedStructural",
        name = "Shared Structural",
    })
    firstAuthorHost.shared.data.owner("Snapshot", {
        id = "test.shared.structural.first",
        default = "first",
    })

    local second, secondAuthorHost = createSharedHost(self.harness, "shared-structural-b", {
        id = "SharedStructural",
        name = "Shared Structural",
    })
    secondAuthorHost.shared.data.owner("Snapshot", {
        id = "test.shared.structural.second",
        default = "second",
    })

    local firstRecord = self.harness.moduleHost.getRecord(first)
    local secondRecord = self.harness.moduleHost.getRecord(second)

    lu.assertEquals(
        firstRecord.definition._structuralFingerprint,
        secondRecord.definition._structuralFingerprint
    )

    self.harness.moduleHost.prepareDefinition(owner, {
        id = "SharedStructural",
        name = "Shared Structural",
    })
    self.harness.moduleHost.prepareDefinition(owner, {
        id = "SharedStructural",
        name = "Shared Structural",
    })
    lu.assertNil(owner.requiresFullReload)
end

function TestShared:testListenAndEmitDeliverPayload()
    local received = {}
    activateHost(self.harness, "shared-listener", {
        configureHost = function(authorHost)
            authorHost.shared.listen("test.events", "changed", function(payload)
                received[#received + 1] = {
                    payload = payload,
                }
            end)
        end,
    })
    local _, emitter = activateHost(self.harness, "shared-emitter")

    local ok, delivered = emitter.shared.emit("test.events", "changed", { value = 42 })

    lu.assertTrue(ok)
    lu.assertEquals(delivered, 1)
    lu.assertEquals(received[1].payload, { value = 42 })
end

function TestShared:testEmitWithoutListenersReturnsZeroDeliveries()
    local _, emitter = activateHost(self.harness, "shared-no-listeners")

    local ok, delivered = emitter.shared.emit("test.missing", "changed", {})

    lu.assertTrue(ok)
    lu.assertEquals(delivered, 0)
end

function TestShared:testDisabledEmitterIsSkipped()
    local delivered = 0
    activateHost(self.harness, "shared-disabled-emitter-listener", {
        configureHost = function(authorHost)
            authorHost.shared.listen("test.disabled-emitter", "changed", function()
                delivered = delivered + 1
            end)
        end,
    })
    local _, emitter = activateHost(self.harness, "shared-disabled-emitter", {
        config = {
            Enabled = false,
        },
    })

    local ok, count = emitter.shared.emit("test.disabled-emitter", "changed", {})

    lu.assertTrue(ok)
    lu.assertEquals(count, 0)
    lu.assertEquals(delivered, 0)
end

function TestShared:testDisabledListenerIsSkipped()
    local delivered = 0
    activateHost(self.harness, "shared-disabled-listener", {
        config = {
            Enabled = false,
        },
        configureHost = function(authorHost)
            authorHost.shared.listen("test.disabled-listener", "changed", function()
                delivered = delivered + 1
            end)
        end,
    })
    local _, emitter = activateHost(self.harness, "shared-disabled-listener-emitter")

    local ok, count = emitter.shared.emit("test.disabled-listener", "changed", {})

    lu.assertTrue(ok)
    lu.assertEquals(count, 0)
    lu.assertEquals(delivered, 0)
end

function TestShared:testNestedEventsAreQueued()
    local order = {}
    local _, emitter = activateHost(self.harness, "shared-nested-emitter")
    activateHost(self.harness, "shared-nested-listener", {
        configureHost = function(authorHost)
            authorHost.shared.listen("test.nested", "first", function(payload)
                order[#order + 1] = payload.step
                local ok = emitter.shared.emit("test.nested", "second", { step = "second" })
                lu.assertTrue(ok)
            end)
            authorHost.shared.listen("test.nested", "second", function(payload)
                order[#order + 1] = payload.step
            end)
        end,
    })

    local ok, delivered = emitter.shared.emit("test.nested", "first", { step = "first" })

    lu.assertTrue(ok)
    lu.assertEquals(delivered, 2)
    lu.assertEquals(order, {
        "first",
        "second",
    })
end

function TestShared:testListenerFailureLogsAndContinues()
    local warnings = {}
    self.harness.env.print = function(message)
        warnings[#warnings + 1] = message
    end
    local delivered = 0
    activateHost(self.harness, "shared-failing-listener-a", {
        configureHost = function(authorHost)
            authorHost.shared.listen("test.listener-failure", "changed", function()
                error("listener boom")
            end)
        end,
    })
    activateHost(self.harness, "shared-failing-listener-b", {
        configureHost = function(authorHost)
            authorHost.shared.listen("test.listener-failure", "changed", function()
                delivered = delivered + 1
            end)
        end,
    })
    local _, emitter = activateHost(self.harness, "shared-failing-listener-emitter")

    local ok, count = emitter.shared.emit("test.listener-failure", "changed", {})

    lu.assertTrue(ok)
    lu.assertEquals(count, 2)
    lu.assertEquals(delivered, 1)
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "shared.listener_failed")
    lu.assertStrContains(warnings[1], "listener boom")
end

function TestShared:testListenerRegistrationRejectsAfterActivationBegins()
    local _, authorHost = activateHost(self.harness, "shared-listen-after-activation")

    lu.assertErrorMsgContains("cannot listen after activation begins", function()
        authorHost.shared.listen("test.invalid", "changed", function() end)
    end)
end

function TestShared:testEmitRejectsBeforeActivation()
    local _, authorHost = createSharedHost(self.harness, "shared-emit-before-activation")

    lu.assertErrorMsgContains("requires host.activate() before it can run", function()
        authorHost.shared.emit("test.invalid", "changed", {})
    end)
end

function TestShared:testInvalidListenInputsAreRejected()
    local _, authorHost = createSharedHost(self.harness, "shared-invalid-listen")

    lu.assertErrorMsgContains("id must be a non-empty string", function()
        authorHost.shared.listen("", "changed", function() end)
    end)
    lu.assertErrorMsgContains("event name must be a non-empty string", function()
        authorHost.shared.listen("test.invalid", "", function() end)
    end)
    lu.assertErrorMsgContains("callback must be a function", function()
        authorHost.shared.listen("test.invalid", "changed", nil)
    end)
end

function TestShared:testInvalidEmitInputsAreRejected()
    local _, authorHost = activateHost(self.harness, "shared-invalid-emit")

    lu.assertErrorMsgContains("id must be a non-empty string", function()
        authorHost.shared.emit("", "changed", {})
    end)
    lu.assertErrorMsgContains("eventName must be a non-empty string", function()
        authorHost.shared.emit("test.invalid", "", {})
    end)
end

function TestShared:testDeclaredDataPublishesOwnerAndDrawWrites()
    local publisher = createSharedModule(self.harness, "test-shared-data-publisher", {
        id = "DeclaredSharedPublisher",
        name = "Declared Shared Publisher",
        shared = {
            Active = {
                id = "test.declared.shared.active",
                access = "owner",
                default = false,
            },
        },
        drawTab = function(_, state)
            state.shared.set("Active", true)
        end,
    })
    local _, readerStore = createSharedModule(self.harness, "test-shared-data-reader", {
        id = "DeclaredSharedReader",
        name = "Declared Shared Reader",
        shared = {
            Active = {
                id = "test.declared.shared.active",
                access = "reader",
                fallback = false,
            },
        },
    })

    activateAndEnableHost(self.harness, publisher, "test-shared-data-publisher")
    lu.assertFalse(readerStore.shared.read("Active"))

    self.harness.moduleHost.getLiveHost("test-shared-data-publisher").drawTab()
    lu.assertTrue(readerStore.shared.read("Active"))
    lu.assertErrorMsgContains("does not support set", function()
        readerStore.shared.set("Active", false)
    end)
end

function TestShared:testDeclaredDataReadsTableViews()
    local publisher = createSharedModule(self.harness, "test-shared-data-table-publisher", {
        id = "DeclaredSharedTablePublisher",
        name = "Declared Shared Table Publisher",
        shared = {
            Availability = {
                id = "test.declared.shared.availability",
                access = "owner",
                default = {
                    active = false,
                    available = {},
                },
            },
        },
        drawTab = function(_, state)
            state.shared.set("Availability", {
                active = true,
                available = {
                    Apollo = false,
                },
            })
        end,
    })
    local _, readerStore = createSharedModule(self.harness, "test-shared-data-table-reader", {
        id = "DeclaredSharedTableReader",
        name = "Declared Shared Table Reader",
        shared = {
            Availability = {
                id = "test.declared.shared.availability",
                access = "reader",
                fallback = {
                    active = false,
                    available = {},
                },
            },
        },
    })

    activateAndEnableHost(self.harness, publisher, "test-shared-data-table-publisher")
    lu.assertFalse(readerStore.shared.read("Availability").active)

    self.harness.moduleHost.getLiveHost("test-shared-data-table-publisher").drawTab()
    local availability = readerStore.shared.read("Availability")
    lu.assertTrue(availability.active)
    lu.assertFalse(availability.available.Apollo)
    lu.assertErrorMsgContains("read-only", function()
        availability.available.Apollo = true
    end)
end

function TestShared:testDeclaredDataOwnerWritesCopyTables()
    local publisher, publisherStore = createSharedModule(self.harness, "test-shared-data-copy-publisher", {
        shared = {
            Snapshot = {
                id = "test.declared.shared.copy",
                access = "owner",
                default = {},
            },
        },
    })
    local _, readerStore = createSharedModule(self.harness, "test-shared-data-copy-reader", {
        shared = {
            Snapshot = {
                id = "test.declared.shared.copy",
                access = "reader",
                fallback = {},
            },
        },
    })

    local snapshot = {
        nested = {
            value = 1,
        },
    }
    activateAndEnableHost(self.harness, publisher, "test-shared-data-copy-publisher")
    lu.assertTrue(publisherStore.shared.set("Snapshot", snapshot))
    snapshot.nested.value = 2

    local firstRead = readerStore.shared.read("Snapshot")
    lu.assertEquals(firstRead.nested.value, 1)
    lu.assertErrorMsgContains("read-only", function()
        firstRead.nested.value = 3
    end)

    local secondRead = readerStore.shared.read("Snapshot")
    lu.assertEquals(secondRead.nested.value, 1)
end

function TestShared:testDeclaredDataRejectsInvalidValues()
    local _, store = createSharedModule(self.harness, "test-shared-data-invalid", {
        shared = {
            Snapshot = {
                id = "test.declared.shared.invalid",
                access = "owner",
            },
        },
    })

    lu.assertErrorMsgContains("value must not be nil", function()
        store.shared.set("Snapshot", nil)
    end)
    lu.assertErrorMsgContains("value must be a scalar or table", function()
        store.shared.set("Snapshot", function() end)
    end)
    lu.assertErrorMsgContains("table keys must be strings or numbers", function()
        store.shared.set("Snapshot", {
            [{}] = true,
        })
    end)
    lu.assertErrorMsgContains("table keys must be strings or numbers", function()
        store.shared.set("Snapshot", {
            [true] = true,
        })
    end)
end

function TestShared:testDeclaredDataDifferentOwnerDuplicateFailsActivation()
    local first = createSharedModule(self.harness, "test-shared-data-dupe-a", {
        shared = {
            Snapshot = {
                id = "test.shared.dupe",
                access = "owner",
            },
        },
    })
    local second = createSharedModule(self.harness, "test-shared-data-dupe-b", {
        shared = {
            Snapshot = {
                id = "test.shared.dupe",
                access = "owner",
            },
        },
    })

    activateAndEnableHost(self.harness, first, "test-shared-data-dupe-a")
    local ok, err = second.activate()
    lu.assertFalse(ok)
    lu.assertStrContains(err, "already published")
end

function TestShared:testDeclaredDataSameOwnerHotReloadReplacesPublication()
    local first, firstStore = createSharedModule(self.harness, "test-shared-data-reload", {
        id = "SharedReload",
        name = "Shared Reload",
        shared = {
            Snapshot = {
                id = "test.shared.reload",
                access = "owner",
                default = "first-default",
            },
        },
    })
    local _, readerStore = createSharedModule(self.harness, "test-shared-data-reload-reader", {
        shared = {
            Snapshot = {
                id = "test.shared.reload",
                access = "reader",
                fallback = "fallback",
            },
        },
    })
    activateAndEnableHost(self.harness, first, "test-shared-data-reload")
    firstStore.shared.set("Snapshot", "first-value")

    local second, secondStore = createSharedModule(self.harness, "test-shared-data-reload", {
        id = "SharedReload",
        name = "Shared Reload",
        shared = {
            Snapshot = {
                id = "test.shared.reload",
                access = "owner",
                default = "second-default",
            },
        },
    })
    activateAndEnableHost(self.harness, second, "test-shared-data-reload")

    lu.assertEquals(readerStore.shared.read("Snapshot"), "second-default")
    lu.assertTrue(secondStore.shared.set("Snapshot", "second-value"))
    lu.assertEquals(readerStore.shared.read("Snapshot"), "second-value")
    lu.assertErrorMsgContains("requires the active publishing owner", function()
        firstStore.shared.set("Snapshot", "stale")
    end)
end

function TestShared:testDeclaredDataDisabledOwnerIsInvisibleToReads()
    local publisher, publisherStore = createSharedModule(self.harness, "test-shared-data-disabled", {
        shared = {
            Snapshot = {
                id = "test.shared.disabled",
                access = "owner",
                default = "default",
            },
        },
    })
    local _, readerStore = createSharedModule(self.harness, "test-shared-data-disabled-reader", {
        shared = {
            Snapshot = {
                id = "test.shared.disabled",
                access = "reader",
                fallback = "fallback",
            },
        },
    })
    activateAndEnableHost(self.harness, publisher, "test-shared-data-disabled")
    publisherStore.shared.set("Snapshot", "visible")

    local fullHost = self.harness.moduleHost.getLiveHost("test-shared-data-disabled")
    lu.assertEquals(readerStore.shared.read("Snapshot"), "visible")
    lu.assertTrue(fullHost.setEnabled(false))
    lu.assertEquals(readerStore.shared.read("Snapshot"), "fallback")
    lu.assertTrue(fullHost.setEnabled(true))
    lu.assertEquals(readerStore.shared.read("Snapshot"), "visible")
end
