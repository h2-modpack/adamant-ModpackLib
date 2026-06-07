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
    local module = harness.public.createModule({
        pluginGuid = pluginGuid,
        config = config,
        id = opts.id or "SharedHost",
        name = opts.name or "Shared Host",
    })
    if opts.storage ~= nil then
        module.data.define(opts.storage)
    end
    module.ui.tab(function() end)
    return module, module, nil
end

local function activateModule(harness, pluginGuid, opts)
    local host, authorModule, state = createSharedHost(harness, pluginGuid, opts)
    if opts and opts.configureHost then
        opts.configureHost(authorModule, host, state)
    end
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))
    return host, authorModule, state
end

local function activateAndEnableHost(harness, host, pluginGuid)
    lu.assertTrue(host.activate())
    local liveModule = harness.managedModule.getLiveModule(pluginGuid)
    lu.assertNotNil(liveModule)
    lu.assertTrue(liveModule.setEnabled(true))
    return liveModule
end

local function getLiveStore(harness, pluginGuid)
    local liveModule = harness.managedModule.getLiveModule(pluginGuid)
    local record = harness.managedModule.getRecord(liveModule)
    return record and record.store or nil
end

local function getLiveRuntime(harness, pluginGuid)
    local liveModule = harness.managedModule.getLiveModule(pluginGuid)
    local record = harness.managedModule.getRecord(liveModule)
    return record and record.runtime or nil
end

local function createSharedModule(harness, pluginGuid, opts)
    opts = opts or {}
    local host, err = harness.public.createModule({
        pluginGuid = pluginGuid,
        config = opts.config or {},
        modpack = "test-pack",
        id = opts.id or ("Shared" .. tostring(pluginGuid):gsub("[^%w_]", "")),
        name = opts.name or pluginGuid,
    })
    lu.assertNil(err)
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
    host.ui.tab(function(callbackHost, ui)
        return (opts.drawTab or function() end)(ui.draw, ui.data, ui.actions, ui, callbackHost)
    end)

    local storeProxy = {
        shared = {},
    }
    setmetatable(storeProxy.shared, {
        __index = function(_, key)
            return function(...)
                local store = getLiveStore(harness, pluginGuid)
                return store.shared[key](...)
            end
        end,
    })
    return host, storeProxy
end

function TestShared:setUp()
    self.harness = createLibHarness()
    self.shared = self.harness.shared
end

function TestShared:testPublicSurfaceIsClosed()
    lu.assertNil(self.harness.public.shared)
end

function TestShared:testServiceSurfaceExposesInstallAndData()
    lu.assertEquals(type(self.shared.installForModule), "function")
    lu.assertEquals(type(self.shared.data), "table")
    lu.assertNil(self.shared.provideForHost)
    lu.assertNil(self.shared.pollForHost)
    lu.assertNil(self.shared.notifyProviderChangedForHost)
end

function TestShared:testAuthorSurfaceExposesDataAndEvents()
    local _, authorModule = createSharedHost(self.harness, "shared-author-surface")

    lu.assertEquals(type(authorModule.shared.data), "table")
    lu.assertEquals(type(authorModule.shared.data.owner), "function")
    lu.assertEquals(type(authorModule.shared.data.reader), "function")
    lu.assertEquals(type(authorModule.shared.listen), "function")
    lu.assertNil(authorModule.shared.emit)
    lu.assertNil(authorModule.shared.provide)
    lu.assertNil(authorModule.shared.poll)
end

function TestShared:testSharedDataDeclarationsDoNotAffectStructuralFingerprint()
    local owner = {}
    local _, firstAuthorModule = createSharedHost(self.harness, "shared-structural-a", {
        id = "SharedStructural",
        name = "Shared Structural",
    })
    firstAuthorModule.shared.data.owner("Snapshot", {
        id = "test.shared.structural.first",
        default = "first",
    })
    lu.assertTrue(firstAuthorModule.activate())

    local _, secondAuthorModule = createSharedHost(self.harness, "shared-structural-b", {
        id = "SharedStructural",
        name = "Shared Structural",
    })
    secondAuthorModule.shared.data.owner("Snapshot", {
        id = "test.shared.structural.second",
        default = "second",
    })
    lu.assertTrue(secondAuthorModule.activate())

    local firstRecord = self.harness.managedModule.getRecord(self.harness.managedModule.getLiveModule("shared-structural-a"))
    local secondRecord = self.harness.managedModule.getRecord(self.harness.managedModule.getLiveModule("shared-structural-b"))

    lu.assertEquals(
        firstRecord.definition._structuralFingerprint,
        secondRecord.definition._structuralFingerprint
    )

    self.harness.managedModule.prepareDefinition(owner, {
        id = "SharedStructural",
        name = "Shared Structural",
    })
    self.harness.managedModule.prepareDefinition(owner, {
        id = "SharedStructural",
        name = "Shared Structural",
    })
    lu.assertNil(owner.requiresFullReload)
end

function TestShared:testListenAndEmitDeliverPayload()
    local received = {}
    activateModule(self.harness, "shared-listener", {
        configureHost = function(authorModule)
            authorModule.shared.listen("test.events", "changed", function(callbackHost, runtime, payload)
                received[#received + 1] = {
                    payload = payload,
                    runtime = runtime,
                    host = callbackHost,
                }
            end)
        end,
    })
    activateModule(self.harness, "shared-emitter")
    local emitter = getLiveRuntime(self.harness, "shared-emitter")

    local ok, delivered = emitter.shared.emit("test.events", "changed", { value = 42 })

    lu.assertTrue(ok)
    lu.assertEquals(delivered, 1)
    lu.assertEquals(received[1].payload, { value = 42 })
    lu.assertEquals(received[1].runtime.data.read("Enabled"), true)
    lu.assertEquals(received[1].host.getOwnerId(), "shared-listener")
end

function TestShared:testEmitWithoutListenersReturnsZeroDeliveries()
    activateModule(self.harness, "shared-no-listeners")
    local emitter = getLiveRuntime(self.harness, "shared-no-listeners")

    local ok, delivered = emitter.shared.emit("test.missing", "changed", {})

    lu.assertTrue(ok)
    lu.assertEquals(delivered, 0)
end

function TestShared:testDisabledEmitterIsSkipped()
    local delivered = 0
    activateModule(self.harness, "shared-disabled-emitter-listener", {
        configureHost = function(authorModule)
            authorModule.shared.listen("test.disabled-emitter", "changed", function()
                delivered = delivered + 1
            end)
        end,
    })
    activateModule(self.harness, "shared-disabled-emitter", {
        config = {
            Enabled = false,
        },
    })
    local emitter = getLiveRuntime(self.harness, "shared-disabled-emitter")

    local ok, count = emitter.shared.emit("test.disabled-emitter", "changed", {})

    lu.assertTrue(ok)
    lu.assertEquals(count, 0)
    lu.assertEquals(delivered, 0)
end

function TestShared:testDisabledListenerIsSkipped()
    local delivered = 0
    activateModule(self.harness, "shared-disabled-listener", {
        config = {
            Enabled = false,
        },
        configureHost = function(authorModule)
            authorModule.shared.listen("test.disabled-listener", "changed", function()
                delivered = delivered + 1
            end)
        end,
    })
    activateModule(self.harness, "shared-disabled-listener-emitter")
    local emitter = getLiveRuntime(self.harness, "shared-disabled-listener-emitter")

    local ok, count = emitter.shared.emit("test.disabled-listener", "changed", {})

    lu.assertTrue(ok)
    lu.assertEquals(count, 0)
    lu.assertEquals(delivered, 0)
end

function TestShared:testNestedEventsAreQueued()
    local order = {}
    activateModule(self.harness, "shared-nested-emitter")
    local emitter = getLiveRuntime(self.harness, "shared-nested-emitter")
    activateModule(self.harness, "shared-nested-listener", {
        configureHost = function(authorModule)
            authorModule.shared.listen("test.nested", "first", function(_, _, payload)
                order[#order + 1] = payload.step
                local ok = emitter.shared.emit("test.nested", "second", { step = "second" })
                lu.assertTrue(ok)
            end)
            authorModule.shared.listen("test.nested", "second", function(_, _, payload)
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
    activateModule(self.harness, "shared-failing-listener-a", {
        configureHost = function(authorModule)
            authorModule.shared.listen("test.listener-failure", "changed", function()
                error("listener boom")
            end)
        end,
    })
    activateModule(self.harness, "shared-failing-listener-b", {
        configureHost = function(authorModule)
            authorModule.shared.listen("test.listener-failure", "changed", function()
                delivered = delivered + 1
            end)
        end,
    })
    activateModule(self.harness, "shared-failing-listener-emitter")
    local emitter = getLiveRuntime(self.harness, "shared-failing-listener-emitter")

    local ok, count = emitter.shared.emit("test.listener-failure", "changed", {})

    lu.assertTrue(ok)
    lu.assertEquals(count, 2)
    lu.assertEquals(delivered, 1)
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "shared.listener_failed")
    lu.assertStrContains(warnings[1], "listener boom")
end

function TestShared:testListenerRegistrationRejectsAfterActivationBegins()
    local _, authorModule = activateModule(self.harness, "shared-listen-after-activation")

    lu.assertErrorMsgContains("cannot be called after module activation begins", function()
        authorModule.shared.listen("test.invalid", "changed", function() end)
    end)
end

function TestShared:testAuthorSharedDoesNotExposeEmit()
    local _, authorModule = createSharedHost(self.harness, "shared-emit-before-activation")

    lu.assertNil(authorModule.shared.emit)
end

function TestShared:testInvalidListenInputsAreRejected()
    local _, authorModule = createSharedHost(self.harness, "shared-invalid-listen")

    lu.assertErrorMsgContains("id must be a non-empty string", function()
        authorModule.shared.listen("", "changed", function() end)
    end)
    lu.assertErrorMsgContains("event name must be a non-empty string", function()
        authorModule.shared.listen("test.invalid", "", function() end)
    end)
    lu.assertErrorMsgContains("callback must be a function", function()
        authorModule.shared.listen("test.invalid", "changed", nil)
    end)
end

function TestShared:testInvalidEmitInputsAreRejected()
    activateModule(self.harness, "shared-invalid-emit")
    local runtime = getLiveRuntime(self.harness, "shared-invalid-emit")

    lu.assertErrorMsgContains("id must be a non-empty string", function()
        runtime.shared.emit("", "changed", {})
    end)
    lu.assertErrorMsgContains("eventName must be a non-empty string", function()
        runtime.shared.emit("test.invalid", "", {})
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
    local reader, readerStore = createSharedModule(self.harness, "test-shared-data-reader", {
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
    activateAndEnableHost(self.harness, reader, "test-shared-data-reader")
    lu.assertFalse(readerStore.shared.read("Active"))

    self.harness.managedModule.getLiveModule("test-shared-data-publisher").drawTab()
    lu.assertTrue(readerStore.shared.read("Active"))
    lu.assertErrorMsgContains("does not support set", function()
        readerStore.shared.set("Active", false)
    end)
end

function TestShared:testDeclaredDataPublishesOwnerOnActivate()
    local publisher = createSharedModule(self.harness, "test-shared-data-activate-publisher", {
        id = "DeclaredSharedActivatePublisher",
        name = "Declared Shared Activate Publisher",
        shared = {
            Active = {
                id = "test.declared.shared.activate",
                access = "owner",
                default = false,
            },
        },
    })
    publisher.onActivate(function(_, runtime)
        runtime.shared.set("Active", true)
    end)
    local reader, readerStore = createSharedModule(self.harness, "test-shared-data-activate-reader", {
        id = "DeclaredSharedActivateReader",
        name = "Declared Shared Activate Reader",
        shared = {
            Active = {
                id = "test.declared.shared.activate",
                access = "reader",
                fallback = false,
            },
        },
    })

    activateAndEnableHost(self.harness, reader, "test-shared-data-activate-reader")
    activateAndEnableHost(self.harness, publisher, "test-shared-data-activate-publisher")

    lu.assertTrue(readerStore.shared.read("Active"))
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
    local reader, readerStore = createSharedModule(self.harness, "test-shared-data-table-reader", {
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
    activateAndEnableHost(self.harness, reader, "test-shared-data-table-reader")
    lu.assertFalse(readerStore.shared.read("Availability").active)

    self.harness.managedModule.getLiveModule("test-shared-data-table-publisher").drawTab()
    local availability = readerStore.shared.read("Availability")
    lu.assertTrue(availability.active)
    lu.assertFalse(availability.available.Apollo)
    lu.assertErrorMsgContains("read-only", function()
        availability.available.Apollo = true
    end)
end

function TestShared:testDeclaredDataTableViewsSupportIpairs()
    local publisher, publisherStore = createSharedModule(self.harness, "test-shared-data-list-publisher", {
        shared = {
            Snapshot = {
                id = "test.declared.shared.list",
                access = "owner",
                default = {},
            },
        },
    })
    local reader, readerStore = createSharedModule(self.harness, "test-shared-data-list-reader", {
        shared = {
            Snapshot = {
                id = "test.declared.shared.list",
                access = "reader",
                fallback = {},
            },
        },
    })

    activateAndEnableHost(self.harness, publisher, "test-shared-data-list-publisher")
    activateAndEnableHost(self.harness, reader, "test-shared-data-list-reader")
    lu.assertTrue(publisherStore.shared.set("Snapshot", {
        "Apollo",
        "Athena",
        nested = {
            "Zeus",
        },
    }))

    local snapshot = readerStore.shared.read("Snapshot")
    local names = {}
    for _, name in ipairs(snapshot) do
        names[#names + 1] = name
    end
    lu.assertEquals(names, { "Apollo", "Athena" })

    local nestedNames = {}
    for _, name in ipairs(snapshot.nested) do
        nestedNames[#nestedNames + 1] = name
    end
    lu.assertEquals(nestedNames, { "Zeus" })
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
    local reader, readerStore = createSharedModule(self.harness, "test-shared-data-copy-reader", {
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
    activateAndEnableHost(self.harness, reader, "test-shared-data-copy-reader")
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
    local publisher, store = createSharedModule(self.harness, "test-shared-data-invalid", {
        shared = {
            Snapshot = {
                id = "test.declared.shared.invalid",
                access = "owner",
            },
        },
    })
    activateAndEnableHost(self.harness, publisher, "test-shared-data-invalid")

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

function TestShared:testDeclaredDataFailedMultiOwnerActivationDoesNotPublishPartialRecord()
    local first = createSharedModule(self.harness, "test-shared-data-partial-dupe-a", {
        shared = {
            Existing = {
                id = "test.shared.partial.existing",
                access = "owner",
                default = "existing",
            },
        },
    })
    local reader, readerStore = createSharedModule(self.harness, "test-shared-data-partial-reader", {
        shared = {
            Unique = {
                id = "test.shared.partial.unique",
                access = "reader",
                fallback = "fallback",
            },
        },
    })
    local _, second = createSharedHost(self.harness, "test-shared-data-partial-dupe-b")
    second.shared.data.owner("Unique", {
        id = "test.shared.partial.unique",
        default = "partial",
    })
    second.shared.data.owner("Existing", {
        id = "test.shared.partial.existing",
        default = "duplicate",
    })
    local third = createSharedModule(self.harness, "test-shared-data-partial-clean-publisher", {
        shared = {
            Unique = {
                id = "test.shared.partial.unique",
                access = "owner",
                default = "clean",
            },
        },
    })

    activateAndEnableHost(self.harness, first, "test-shared-data-partial-dupe-a")
    activateAndEnableHost(self.harness, reader, "test-shared-data-partial-reader")
    local ok, err = second.activate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "already published")
    lu.assertEquals(readerStore.shared.read("Unique"), "fallback")
    activateAndEnableHost(self.harness, third, "test-shared-data-partial-clean-publisher")
    lu.assertEquals(readerStore.shared.read("Unique"), "clean")
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
    local reader, readerStore = createSharedModule(self.harness, "test-shared-data-reload-reader", {
        shared = {
            Snapshot = {
                id = "test.shared.reload",
                access = "reader",
                fallback = "fallback",
            },
        },
    })
    activateAndEnableHost(self.harness, reader, "test-shared-data-reload-reader")
    activateAndEnableHost(self.harness, first, "test-shared-data-reload")
    local staleFirstStore = getLiveStore(self.harness, "test-shared-data-reload")
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
        staleFirstStore.shared.set("Snapshot", "stale")
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
    local reader, readerStore = createSharedModule(self.harness, "test-shared-data-disabled-reader", {
        shared = {
            Snapshot = {
                id = "test.shared.disabled",
                access = "reader",
                fallback = "fallback",
            },
        },
    })
    activateAndEnableHost(self.harness, reader, "test-shared-data-disabled-reader")
    activateAndEnableHost(self.harness, publisher, "test-shared-data-disabled")
    publisherStore.shared.set("Snapshot", "visible")

    local liveModule = self.harness.managedModule.getLiveModule("test-shared-data-disabled")
    lu.assertEquals(readerStore.shared.read("Snapshot"), "visible")
    lu.assertTrue(liveModule.setEnabled(false))
    lu.assertEquals(readerStore.shared.read("Snapshot"), "fallback")
    lu.assertTrue(liveModule.setEnabled(true))
    lu.assertEquals(readerStore.shared.read("Snapshot"), "visible")
end
