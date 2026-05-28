local lu = require("luaunit")
local createModuleHostHarness = require("tests/harness/create_module_host_harness")

TestModuleHost_CreateModule = {}

local function createTestModule(h, opts)
    local module, err = h.public.createModule({
        pluginGuid = opts.pluginGuid,
        config = opts.config,
        modpack = opts.modpack,
        id = opts.id,
        name = opts.name,
        shortName = opts.shortName,
        tooltip = opts.tooltip,
    })
    if module == nil then
        return nil, err
    end
    if opts.storage ~= nil then
        module.data.define(opts.storage)
    end
    if opts.cache ~= nil then
        module.cache.define(opts.cache)
    end
    if opts.actions ~= nil then
        module.actions.define(opts.actions)
    end
    if opts.hashGroupPlan ~= nil then
        module.hashGroups.define(opts.hashGroupPlan)
    end
    if opts.onCommit ~= nil then
        module.onCommit(opts.onCommit)
    end
    if opts.drawTab ~= nil then
        module.ui.tab(function(host, ui)
            return opts.drawTab(ui.draw, ui.data, ui.actions, ui, host)
        end)
    end
    if opts.drawQuickContent ~= nil then
        module.ui.quickContent(function(host, ui)
            return opts.drawQuickContent(ui.draw, ui.data, ui.actions, ui, host)
        end)
    end
    return module, nil
end

local function getLiveStore(h, pluginGuid)
    local liveHost = h:liveHost(pluginGuid)
    local record = h.moduleHost.getRecord(liveHost)
    return record and record.store or nil
end

function TestModuleHost_CreateModule:setUp()
    self.h = createModuleHostHarness()
    self.h:captureWarnings()
end

function TestModuleHost_CreateModule:tearDown()
    self.h:restoreWarnings()
end

function TestModuleHost_CreateModule:testCreateModuleRunsCanonicalPipeline()
    local drawContext = nil
    local drawImgui = nil
    local capturedState = nil
    local capturedActions = nil
    local capturedUi = nil
    local capturedCallbackHost = nil
    local drawWidgets = nil
    local drawNav = nil
    local authorSchemaNode = nil
    local authorStateField = nil
    local authorStateFieldAlias = nil
    local authorStateFieldSchemaAlias = nil
    local authorRowValue = nil
    local authorRows = nil
    local authorRowField = nil
    local authorRowFieldAlias = nil
    local authorRowFieldValue = nil
    local capturedFlagValue = nil
    local capturedRowValue = nil
    local runtimeField = nil
    local runtimeRows = nil
    local runtimeRowField = nil
    local config = {}
    local host, store
    local checkRuntimeRefs = false

    host = createTestModule(self.h, {
        pluginGuid = "test-create-module",
        config = config,
        modpack = "create-module-pack",
        id = "CreateModule",
        name = "Create Module",
        storage = {
            { type = "bool", alias = "Flag", default = false },
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                },
            },
        },
        drawTab = function(draw, state, actions, ui, callbackHost)
            drawContext = draw
            drawImgui = draw.imgui
            capturedState = state
            capturedActions = actions
            capturedUi = ui
            capturedCallbackHost = callbackHost
            drawWidgets = draw.widgets
            drawNav = draw.nav
            authorStateField = state.get("Flag")
            authorSchemaNode = authorStateField:schema()
            local rows = state.get("Rows")
            authorRows = rows
            authorRowField = rows:get(1, "Limit")
            if authorRowValue == nil then
                authorRowValue = rows:read(1, "Limit")
            end
            authorStateField:write(true)
            state.write("Rows", 1, "Limit", 3)
            capturedFlagValue = state.read("Flag")
            capturedRowValue = state.read("Rows", 1, "Limit")
            lu.assertErrorMsgContains("storage.invalid_field_args", function()
                state.read("Flag", 1, "Limit")
            end)
            authorStateFieldAlias = authorStateField:alias()
            authorStateFieldSchemaAlias = authorStateField:schema().alias
            authorRowFieldAlias = authorRowField:alias()
            authorRowFieldValue = authorRowField:read()
            lu.assertErrorMsgContains("phase.invalid_runtime_access", function()
                store.read("Flag")
            end)
            if checkRuntimeRefs then
                lu.assertErrorMsgContains("phase.invalid_runtime_access", function()
                    runtimeField:read()
                end)
                lu.assertErrorMsgContains("phase.invalid_runtime_access", function()
                    runtimeRows:read(1, "Limit")
                end)
                lu.assertErrorMsgContains("phase.invalid_runtime_access", function()
                    runtimeRowField:read()
                end)
            end
        end,
    })

    lu.assertNil(self.h:liveHost("test-create-module"))
    host.activate()
    local liveHost = self.h:liveHost("test-create-module")
    store = getLiveStore(self.h, "test-create-module")
    liveHost.drawTab()

    lu.assertNotNil(drawImgui)
    lu.assertNotNil(capturedState)
    lu.assertEquals(type(drawContext.log), "function")
    lu.assertEquals(type(drawContext.logIf), "function")
    lu.assertEquals(type(capturedActions.get), "function")
    lu.assertEquals(type(capturedActions.trigger), "function")
    lu.assertEquals(type(capturedActions.emit), "function")
    lu.assertEquals(capturedUi.draw, drawContext)
    lu.assertEquals(capturedUi.data, capturedState)
    lu.assertEquals(capturedUi.actions, capturedActions)
    lu.assertEquals(capturedCallbackHost.getHostId(), "test-create-module")
    lu.assertFalse(capturedCallbackHost.isEnabled())
    lu.assertNil(capturedActions.hasAny)
    lu.assertEquals(type(drawWidgets.checkbox), "function")
    lu.assertNil(drawWidgets.forStagedState)
    lu.assertEquals(type(drawNav.verticalTabs), "function")
    lu.assertNil(drawNav.isVisible)
    lu.assertNil(drawContext.state)
    lu.assertNil(drawContext.actions)
    lu.assertNil(drawContext.services)
    lu.assertNil(drawContext.field)
    lu.assertNil(capturedState.view)
    lu.assertNil(capturedState.table)
    lu.assertNil(capturedState.field)
    lu.assertNil(capturedState.reset)
    lu.assertNil(capturedState.getAliasSchema)
    lu.assertEquals(type(capturedState.read), "function")
    lu.assertEquals(type(capturedState.write), "function")
    lu.assertEquals(capturedFlagValue, true)
    lu.assertEquals(capturedRowValue, 3)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        capturedState.read("Flag")
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        capturedState.write("Flag", false)
    end)
    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(type(store.get), "function")
    lu.assertEquals(type(store.read), "function")
    lu.assertNil(store.table)
    lu.assertNil(store.getAliasSchema)
    lu.assertNil(store.write)
    runtimeField = store.get("Flag")
    runtimeRows = store.get("Rows")
    runtimeRowField = runtimeRows:get(1, "Limit")
    lu.assertEquals(runtimeField:read(), false)
    lu.assertEquals(runtimeField:alias(), "Flag")
    lu.assertEquals(runtimeRows:count(), 1)
    lu.assertEquals(runtimeRows:read(1, "Limit"), 2)
    lu.assertEquals(runtimeRowField:read(), 2)
    checkRuntimeRefs = true
    liveHost.drawTab()
    lu.assertEquals(store.read("Flag"), false)
    lu.assertEquals(store.read("Rows", 1, "Limit"), 2)
    lu.assertErrorMsgContains("storage.invalid_field_args", function()
        store.read("Flag", 1, "Limit")
    end)
    liveHost.flush()
    lu.assertEquals(store.read("Flag"), true)
    lu.assertEquals(runtimeField:read(), true)
    lu.assertEquals(self.h.moduleRegistry.getPluginInfo("test-create-module"), {
        pluginGuid = "test-create-module",
        packId = "create-module-pack",
        moduleId = "CreateModule",
        name = "Create Module",
    })
    lu.assertNotNil(authorSchemaNode)
    lu.assertEquals(authorSchemaNode.alias, "Flag")
    lu.assertEquals(authorSchemaNode.type, "bool")
    lu.assertEquals(authorStateFieldAlias, "Flag")
    lu.assertEquals(authorStateFieldSchemaAlias, "Flag")
    lu.assertEquals(authorRowValue, 2)
    lu.assertEquals(authorRowFieldAlias, "Limit")
    lu.assertEquals(authorRowFieldValue, 3)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        authorStateField:alias()
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        authorRows:count()
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        authorRows:read(1, "Limit")
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        authorRows:get(1, "Limit")
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        authorRows:write(1, "Limit", 4)
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        authorRowField:read()
    end)
    local liveRecord = self.h.moduleHost.getRecord(liveHost)
    lu.assertEquals(type(liveRecord.definition._structuralFingerprint), "string")
end

function TestModuleHost_CreateModule:testDrawCallbacksReuseStableFacades()
    local calls = {}
    local host = createTestModule(self.h, {
        pluginGuid = "test-create-module-stable-draw-objects",
        config = {},
        modpack = "create-module-pack",
        id = "StableDrawObjects",
        name = "Stable Draw Objects",
        storage = {},
        drawTab = function(draw, state, actions)
            calls[#calls + 1] = {
                draw = draw,
                imgui = draw.imgui,
                widgets = draw.widgets,
                nav = draw.nav,
                state = state,
                actions = actions,
            }
        end,
    })

    host.activate()
    local liveHost = self.h:liveHost("test-create-module-stable-draw-objects")
    liveHost.drawTab()
    liveHost.drawTab()
    liveHost.drawTab()

    lu.assertEquals(#calls, 3)
    lu.assertEquals(calls[1].draw, calls[2].draw)
    lu.assertEquals(calls[1].draw, calls[3].draw)
    lu.assertEquals(calls[1].imgui, self.h.rom.ImGui)
    lu.assertEquals(calls[2].imgui, self.h.rom.ImGui)
    lu.assertEquals(calls[3].imgui, self.h.rom.ImGui)
    lu.assertEquals(calls[1].widgets, calls[2].widgets)
    lu.assertEquals(calls[2].widgets, calls[3].widgets)
    lu.assertEquals(calls[1].nav, calls[2].nav)
    lu.assertEquals(calls[2].nav, calls[3].nav)
    lu.assertEquals(calls[1].state, calls[2].state)
    lu.assertEquals(calls[1].state, calls[3].state)
    lu.assertEquals(calls[1].actions, calls[2].actions)
    lu.assertEquals(calls[1].actions, calls[3].actions)
end

function TestModuleHost_CreateModule:testPackedWidgetsUseDrawStateScopedAliases()
    local config = { Packed = 0 }
    local checkboxLabels = {}
    local changed = false
    self.h.rom.ImGui.Checkbox = function(label, current)
        checkboxLabels[#checkboxLabels + 1] = label
        if label == "First##Packed:First" then
            return true, true
        end
        return current, false
    end

    local host = createTestModule(self.h, {
        pluginGuid = "test-create-module-packed-widget-owner",
        config = config,
        modpack = "create-module-pack",
        id = "PackedWidgetOwner",
        name = "Packed Widget Owner",
        storage = {
            {
                type = "packedInt",
                alias = "Packed",
                bits = {
                    { alias = "First", offset = 0, width = 1, type = "bool", default = false },
                    { alias = "Second", offset = 1, width = 1, type = "bool", default = false },
                },
            },
        },
        drawTab = function(draw, state)
            local field = state.get("Packed")
            changed = draw.widgets.packedCheckboxList(field, {
                slotCount = 2,
            })
        end,
    })

    host.activate()
    local store = getLiveStore(self.h, "test-create-module-packed-widget-owner")
    self.h:liveHost("test-create-module-packed-widget-owner").drawTab()

    lu.assertTrue(changed)
    lu.assertEquals(checkboxLabels, {
        "First##Packed:First",
        "Second##Packed:Second",
    })
    lu.assertEquals(store.read("Packed"), 0)

    self.h:liveHost("test-create-module-packed-widget-owner").flush()
    lu.assertEquals(store.read("Packed"), 1)
    lu.assertEquals(config.Packed, 1)
end

function TestModuleHost_CreateModule:testDrawFacadeIsSharedAcrossHosts()
    local firstDraw = nil
    local secondDraw = nil
    local firstUi = nil
    local secondUi = nil
    local firstCallbackHost = nil
    local secondCallbackHost = nil
    local firstHost = createTestModule(self.h, {
        pluginGuid = "test-create-module-shared-draw-a",
        config = {},
        modpack = "create-module-pack",
        id = "SharedDrawA",
        name = "Shared Draw A",
        storage = {},
        drawTab = function(draw, _, _, ui, callbackHost)
            firstDraw = draw
            firstUi = ui
            firstCallbackHost = callbackHost
        end,
    })
    local secondHost = createTestModule(self.h, {
        pluginGuid = "test-create-module-shared-draw-b",
        config = {},
        modpack = "create-module-pack",
        id = "SharedDrawB",
        name = "Shared Draw B",
        storage = {},
        drawTab = function(draw, _, _, ui, callbackHost)
            secondDraw = draw
            secondUi = ui
            secondCallbackHost = callbackHost
        end,
    })

    firstHost.activate()
    secondHost.activate()
    self.h:liveHost("test-create-module-shared-draw-a").drawTab()
    self.h:liveHost("test-create-module-shared-draw-b").drawTab()

    lu.assertNotNil(firstDraw)
    lu.assertEquals(firstDraw, secondDraw)
    lu.assertEquals(firstDraw.widgets, secondDraw.widgets)
    lu.assertEquals(firstDraw.nav, secondDraw.nav)
    lu.assertNotEquals(firstUi, secondUi)
    lu.assertEquals(firstUi.draw, firstDraw)
    lu.assertEquals(secondUi.draw, secondDraw)
    lu.assertEquals(firstCallbackHost.getHostId(), "test-create-module-shared-draw-a")
    lu.assertEquals(secondCallbackHost.getHostId(), "test-create-module-shared-draw-b")
end

function TestModuleHost_CreateModule:testCreateModuleReturnsOnlyModuleDeclarationSurface()
    local host = createTestModule(self.h, {
        pluginGuid = "test-create-module-author-surface",
        config = {},
        modpack = "create-module-pack",
        id = "AuthorSurface",
        name = "Author Surface",
        drawTab = function() end,
    })

    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(type(host.getHostId), "function")
    lu.assertEquals(type(host.getModuleId), "function")
    lu.assertEquals(type(host.getPackId), "function")
    lu.assertNil(host.getIdentity)
    lu.assertEquals(type(host.getMeta), "function")
    lu.assertEquals(type(host.log), "function")
    lu.assertEquals(type(host.logIf), "function")
    lu.assertEquals(type(host.hooks), "table")
    lu.assertEquals(type(host.hooks.wrap), "function")
    lu.assertEquals(type(host.hooks.override), "function")
    lu.assertEquals(type(host.hooks.contextWrap), "function")
    lu.assertEquals(type(host.shared), "table")
    lu.assertNil(host.shared.provide)
    lu.assertNil(host.shared.poll)
    lu.assertEquals(type(host.shared.listen), "function")
    lu.assertEquals(type(host.shared.emit), "function")
    lu.assertEquals(type(host.mutation), "table")
    lu.assertEquals(type(host.mutation.patch), "function")
    lu.assertEquals(type(host.overlays), "table")
    lu.assertEquals(type(host.overlays.order), "table")
    lu.assertEquals(type(host.overlays.createLine), "function")
    lu.assertEquals(type(host.overlays.createTable), "function")
    lu.assertEquals(type(host.overlays.onCommit), "function")
    lu.assertEquals(type(host.overlays.onInterval), "function")
    lu.assertEquals(type(host.overlays.afterHook), "function")
    lu.assertEquals(type(host.activate), "function")
    lu.assertNil(host.tryActivate)
    lu.assertNil(host.read)
    lu.assertNil(host.writeAndFlush)
    lu.assertNil(host.commitIfDirty)
    lu.assertNil(host.applyMutation)
    lu.assertNil(host.setEnabled)
end

function TestModuleHost_CreateModule:testCreateModuleSupportsDeclarativeModuleFacade()
    local config = {}
    local capturedUi = nil
    local capturedHost = nil
    local capturedActionHost = nil
    local capturedActionUiData = nil
    local capturedActionRuntime = nil
    local capturedCommitRuntime = nil
    local capturedCommitHost = nil
    local capturedCommit = nil
    local module, err = self.h.public.createModule({
        pluginGuid = "test-create-module-declarative-facade",
        config = config,
        modpack = "create-module-pack",
        id = "DeclarativeFacade",
        name = "Declarative Facade",
    })

    lu.assertNil(err)
    lu.assertEquals(module.getHostId(), "test-create-module-declarative-facade")
    lu.assertEquals(module.getModuleId(), "DeclarativeFacade")
    lu.assertEquals(module.getPackId(), "create-module-pack")
    lu.assertFalse(module.isEnabled())

    module.data.define({
        { type = "bool", alias = "Flag", default = false },
        { type = "bool", alias = "RuntimeFlag", mode = "runtime", default = false },
    })
    module.actions.define({
        setBoth = function(host, uiData, actionRuntime, value)
            capturedActionHost = host
            capturedActionUiData = uiData
            capturedActionRuntime = actionRuntime
            uiData.write("Flag", value)
            actionRuntime.set("RuntimeFlag", value)
        end,
    })
    module.onCommit(function(host, runtime, commit)
        capturedCommitRuntime = runtime
        capturedCommitHost = host
        capturedCommit = commit
    end)
    module.ui.tab(function(host, ui)
        capturedUi = ui
        capturedHost = host
        ui.actions.trigger("setBoth", true)
    end)

    local ok, activateErr = module.activate()
    lu.assertTrue(ok, tostring(activateErr))

    local liveHost = self.h:liveHost("test-create-module-declarative-facade")
    lu.assertNotNil(liveHost)
    liveHost.drawTab()

    lu.assertEquals(capturedHost.getHostId(), "test-create-module-declarative-facade")
    lu.assertNotNil(capturedUi.draw)
    lu.assertEquals(type(capturedUi.actions.trigger), "function")
    lu.assertEquals(capturedActionHost.getHostId(), "test-create-module-declarative-facade")
    lu.assertEquals(capturedActionUiData, capturedUi.data)
    lu.assertEquals(capturedActionRuntime.read("RuntimeFlag"), true)

    lu.assertTrue(liveHost.commitIfDirty())
    lu.assertEquals(config.Flag, true)
    lu.assertEquals(capturedCommitRuntime.data.read("Flag"), true)
    lu.assertEquals(capturedCommitRuntime.data.runtime.read("RuntimeFlag"), true)
    lu.assertEquals(capturedCommitHost.getHostId(), "test-create-module-declarative-facade")
    lu.assertTrue(capturedCommit.hadConfigChanges())
end

function TestModuleHost_CreateModule:testDeclarativeModuleSharedListenerReceivesRuntimeHostAndPayload()
    local received = nil
    local listener = self.h.public.createModule({
        pluginGuid = "test-create-module-declarative-listener",
        config = {
            Enabled = true,
        },
        modpack = "create-module-pack",
        id = "DeclarativeListener",
        name = "Declarative Listener",
    })
    listener.data.define({
        { type = "bool", alias = "Flag", default = false },
    })
    listener.ui.tab(function() end)
    listener.shared.listen("test.declarative-event", "changed", function(host, runtime, payload)
        received = {
            runtime = runtime,
            host = host,
            payload = payload,
        }
    end)
    lu.assertTrue(listener.activate())

    local emitter = self.h.public.createModule({
        pluginGuid = "test-create-module-declarative-emitter",
        config = {
            Enabled = true,
        },
        modpack = "create-module-pack",
        id = "DeclarativeEmitter",
        name = "Declarative Emitter",
    })
    emitter.ui.tab(function() end)
    lu.assertTrue(emitter.activate())

    local ok, count = emitter.shared.emit("test.declarative-event", "changed", { value = 7 })

    lu.assertTrue(ok)
    lu.assertEquals(count, 1)
    lu.assertEquals(received.payload.value, 7)
    lu.assertEquals(received.host.getHostId(), "test-create-module-declarative-listener")
    lu.assertTrue(received.runtime.data.read("Enabled"))
    lu.assertFalse(received.runtime.data.read("Flag"))
end

function TestModuleHost_CreateModule:testDeclarativeModuleHooksReceiveHostRuntimeAndGameArgs()
    local captured = nil
    local module = self.h.public.createModule({
        pluginGuid = "test-create-module-declarative-hooks",
        config = {
            Enabled = true,
        },
        modpack = "create-module-pack",
        id = "DeclarativeHooks",
        name = "Declarative Hooks",
    })
    module.data.define({
        { type = "int", alias = "Bonus", default = 3 },
    })
    module.ui.tab(function() end)
    module.hooks.wrap("AdamantCreateModuleHookTarget", "bonus", function(host, runtime, base, value)
        captured = {
            host = host,
            runtime = runtime,
            value = value,
        }
        return base(value) + runtime.data.read("Bonus")
    end)

    lu.assertTrue(module.activate())
    local liveHost = self.h:liveHost("test-create-module-declarative-hooks")
    local record = self.h.moduleHost.getRecord(liveHost)
    local slot = record.hookDeclarations.wrap.AdamantCreateModuleHookTarget.slots.bonus
    local result = slot.value(function(value)
        return value + 1
    end, 4)

    lu.assertEquals(result, 8)
    lu.assertEquals(captured.host.getHostId(), "test-create-module-declarative-hooks")
    lu.assertEquals(captured.runtime.data.read("Bonus"), 3)
    lu.assertEquals(captured.value, 4)
end

function TestModuleHost_CreateModule:testDeclarativeModuleActivationIsSingleUse()
    local module = self.h.public.createModule({
        pluginGuid = "test-create-module-declarative-single-activate",
        config = {},
        modpack = "create-module-pack",
        id = "DeclarativeSingleActivate",
        name = "Declarative Single Activate",
    })
    module.ui.tab(function() end)

    lu.assertTrue(module.activate())
    local ok, err = module.activate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "already activated")
end

function TestModuleHost_CreateModule:testHostMutationPatchDeclaresActivationMutation()
    local target = { Value = "base" }
    local patchRuntime = nil
    local patchCallbackHost = nil
    local host = createTestModule(self.h, {
        pluginGuid = "test-create-module-host-mutation-patch",
        config = {
            Enabled = true,
        },
        id = "HostMutationPatch",
        name = "Host Mutation Patch",
        drawTab = function() end,
    })

    host.mutation.patch(function(callbackHost, runtime, plan)
        patchRuntime = runtime
        patchCallbackHost = callbackHost
        plan:set(target, "Value", "patched")
    end)

    local ok, err = host.activate()

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(target.Value, "patched")
    lu.assertNotNil(patchRuntime.data)
    lu.assertEquals(patchCallbackHost.getHostId(), "test-create-module-host-mutation-patch")
    lu.assertNil(patchRuntime.data.table)
    lu.assertNil(patchRuntime.data.getAliasSchema)
end

function TestModuleHost_CreateModule:testHostMutationPatchRejectsAfterActivation()
    local host = createTestModule(self.h, {
        pluginGuid = "test-create-module-host-mutation-after-activation",
        config = {},
        id = "HostMutationAfterActivation",
        name = "Host Mutation After Activation",
        drawTab = function() end,
    })
    host.activate()

    lu.assertErrorMsgContains("after module activation begins", function()
        host.mutation.patch(function() end)
    end)
end

function TestModuleHost_CreateModule:testCreateModuleReturnsErrorAndLogsWarning()
    local host, err = self.h.public.createModule({
        pluginGuid = "test-try-create-module-invalid",
        id = "TryCreateInvalid",
    })

    lu.assertNil(host)
    lu.assertStrContains(err, "config is required")
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "host.create_failed")
    lu.assertStrContains(self.h.warnings[1], "config is required")
    lu.assertNil(self.h:liveHost("test-try-create-module-invalid"))
end

function TestModuleHost_CreateModule:testCreateModuleActivationIsSingleUse()
    local host = createTestModule(self.h, {
        pluginGuid = "test-create-module-single-activate",
        config = {},
        modpack = "create-module-pack",
        id = "SingleActivate",
        name = "Single Activate",
        drawTab = function() end,
    })

    host.activate()
    local ok, err = host.activate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "already activated")
end

function TestModuleHost_CreateModule:testCreateModuleRejectsOwnerOption()
    lu.assertErrorMsgContains("unknown option 'owner'", function()
        self.h:createModuleOrThrow({
            owner = {},
            pluginGuid = "test-create-module-hooks-no-owner",
            config = {},
            id = "HooksNoOwner",
            name = "Hooks No Owner",
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleRejectsLegacyDefinitionOption()
    lu.assertErrorMsgContains("definition table is no longer supported", function()
        self.h:createModuleOrThrow({
            pluginGuid = "test-create-module-legacy-definition",
            config = {},
            definition = {
                id = "LegacyDefinition",
                name = "Legacy Definition",
            },
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleRejectsLegacyTopLevelDeclarations()
    lu.assertErrorMsgContains("unknown option 'storage'", function()
        self.h:createModuleOrThrow({
            pluginGuid = "test-create-module-storage-top-level",
            config = {},
            id = "StorageTopLevel",
            name = "Storage Top Level",
            storage = {},
        })
    end)
    lu.assertErrorMsgContains("unknown option 'drawTab'", function()
        self.h:createModuleOrThrow({
            pluginGuid = "test-create-module-draw-tab-top-level",
            config = {},
            id = "DrawTabTopLevel",
            name = "Draw Tab Top Level",
            drawTab = function() end,
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleTreatsManualMutationAsUnknownOption()
    lu.assertErrorMsgContains("unknown option 'registerManualMutation'", function()
        self.h:createModuleOrThrow({
            pluginGuid = "test-create-module-manual-mutation-unknown",
            config = {},
            id = "ManualMutationUnknown",
            name = "Manual Mutation Unknown",
            registerManualMutation = {
                apply = function() end,
                revert = function() end,
            },
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleTreatsRegisterPatchMutationAsUnknownOption()
    lu.assertErrorMsgContains("unknown option 'registerPatchMutation'", function()
        self.h:createModuleOrThrow({
            pluginGuid = "test-create-module-patch-mutation-unknown",
            config = {},
            id = "PatchMutationUnknown",
            name = "Patch Mutation Unknown",
            registerPatchMutation = function() end,
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleTreatsRegisterSharedAsUnknownOption()
    lu.assertErrorMsgContains("unknown option 'registerShared'", function()
        self.h:createModuleOrThrow({
            pluginGuid = "test-create-module-register-shared-unknown",
            config = {},
            id = "RegisterSharedUnknown",
            name = "Register Shared Unknown",
            registerShared = function() end,
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleTreatsRegisterHooksAsUnknownOption()
    lu.assertErrorMsgContains("unknown option 'registerHooks'", function()
        self.h:createModuleOrThrow({
            pluginGuid = "test-create-module-register-hooks-unknown",
            config = {},
            id = "RegisterHooksUnknown",
            name = "Register Hooks Unknown",
            registerHooks = function() end,
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleTreatsRegisterOverlaysAsUnknownOption()
    lu.assertErrorMsgContains("unknown option 'registerOverlays'", function()
        self.h:createModuleOrThrow({
            pluginGuid = "test-create-module-register-overlays-unknown",
            config = {},
            id = "RegisterOverlaysUnknown",
            name = "Register Overlays Unknown",
            registerOverlays = function() end,
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleFingerprintTracksQuickContentPresenceOnly()
    local stableHost = createTestModule(self.h, {
        pluginGuid = "test-create-module-quick-content-stable",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentStable",
        name = "Quick Content Stable",
        drawTab = function() end,
        drawQuickContent = function() end,
    })
    stableHost.activate()

    local stableReplacement = createTestModule(self.h, {
        pluginGuid = "test-create-module-quick-content-stable",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentStable",
        name = "Quick Content Stable",
        drawTab = function() end,
        drawQuickContent = function() end,
    })
    stableReplacement.activate()

    lu.assertEquals(#self.h.warnings, 0)

    local addedHost = createTestModule(self.h, {
        pluginGuid = "test-create-module-quick-content-added",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentAdded",
        name = "Quick Content Added",
        drawTab = function() end,
    })
    addedHost.activate()

    local addedReplacement = createTestModule(self.h, {
        pluginGuid = "test-create-module-quick-content-added",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentAdded",
        name = "Quick Content Added",
        drawTab = function() end,
        drawQuickContent = function() end,
    })
    addedReplacement.activate()

    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "structural definition changed during hot reload")
end
