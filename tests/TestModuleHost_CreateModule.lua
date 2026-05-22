local lu = require("luaunit")
local createModuleHostHarness = require("tests/harness/create_module_host_harness")

TestModuleHost_CreateModule = {}

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
    local drawServices = nil
    local capturedActions = nil
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

    host, store = self.h.public.createModule({
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
        drawTab = function(draw, state, actions, services)
            drawContext = draw
            drawImgui = draw.imgui
            capturedState = state
            drawServices = services
            capturedActions = actions
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
    liveHost.drawTab()

    lu.assertNotNil(drawImgui)
    lu.assertNotNil(capturedState)
    lu.assertEquals(type(drawServices.log), "function")
    lu.assertEquals(type(drawServices.logIf), "function")
    lu.assertEquals(type(drawServices.isHostEnabled), "function")
    lu.assertEquals(type(drawServices.invokeIntegration), "function")
    lu.assertEquals(type(capturedActions.get), "function")
    lu.assertEquals(type(capturedActions.hasAny), "function")
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
    lu.assertEquals(self.h.hostRegistry.getPluginInfo("test-create-module"), {
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
    local host = self.h.public.createModule({
        pluginGuid = "test-create-module-stable-draw-services",
        config = {},
        modpack = "create-module-pack",
        id = "StableDrawServices",
        name = "Stable Draw Services",
        storage = {},
        drawTab = function(draw, state, actions, services)
            calls[#calls + 1] = {
                draw = draw,
                imgui = draw.imgui,
                widgets = draw.widgets,
                nav = draw.nav,
                state = state,
                actions = actions,
                services = services,
            }
        end,
    })

    host.activate()
    local liveHost = self.h:liveHost("test-create-module-stable-draw-services")
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
    lu.assertEquals(calls[1].services, calls[2].services)
    lu.assertEquals(calls[1].services, calls[3].services)
end

function TestModuleHost_CreateModule:testDrawFacadeIsSharedAcrossHosts()
    local firstDraw = nil
    local secondDraw = nil
    local firstHost = self.h.public.createModule({
        pluginGuid = "test-create-module-shared-draw-a",
        config = {},
        modpack = "create-module-pack",
        id = "SharedDrawA",
        name = "Shared Draw A",
        storage = {},
        drawTab = function(draw)
            firstDraw = draw
        end,
    })
    local secondHost = self.h.public.createModule({
        pluginGuid = "test-create-module-shared-draw-b",
        config = {},
        modpack = "create-module-pack",
        id = "SharedDrawB",
        name = "Shared Draw B",
        storage = {},
        drawTab = function(draw)
            secondDraw = draw
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
end

function TestModuleHost_CreateModule:testCreateModuleReturnsOnlyAuthorHostSurface()
    local host = self.h.public.createModule({
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
    lu.assertEquals(type(host.cache), "table")
    lu.assertEquals(type(host.cache.currentRun.get), "function")
    lu.assertEquals(type(host.hooks), "table")
    lu.assertEquals(type(host.hooks.wrap), "function")
    lu.assertEquals(type(host.hooks.override), "function")
    lu.assertEquals(type(host.hooks.contextWrap), "function")
    lu.assertEquals(type(host.integrations), "table")
    lu.assertEquals(type(host.integrations.register), "function")
    lu.assertEquals(type(host.integrations.invoke), "function")
    lu.assertEquals(type(host.mutation), "table")
    lu.assertEquals(type(host.mutation.patch), "function")
    lu.assertEquals(type(host.overlays), "table")
    lu.assertEquals(type(host.overlays.order), "table")
    lu.assertEquals(type(host.overlays.createLine), "function")
    lu.assertEquals(type(host.overlays.createTable), "function")
    lu.assertEquals(type(host.overlays.onCommit), "function")
    lu.assertEquals(type(host.overlays.onInterval), "function")
    lu.assertEquals(type(host.overlays.afterHook), "function")
    local cacheSurfaceCount = 0
    for key in pairs(host.cache) do
        cacheSurfaceCount = cacheSurfaceCount + 1
        lu.assertTrue(key == "currentRun" or key == "persistent", key)
    end
    lu.assertEquals(cacheSurfaceCount, 2)
    lu.assertEquals(type(host.activate), "function")
    lu.assertNil(host.tryActivate)
    lu.assertNil(host.read)
    lu.assertNil(host.writeAndFlush)
    lu.assertNil(host.commitIfDirty)
    lu.assertNil(host.applyMutation)
    lu.assertNil(host.setEnabled)
end

function TestModuleHost_CreateModule:testHostMutationPatchDeclaresActivationMutation()
    local target = { Value = "base" }
    local patchHost = nil
    local patchStore = nil
    local host, store = self.h.public.createModule({
        pluginGuid = "test-create-module-host-mutation-patch",
        config = {
            Enabled = true,
        },
        id = "HostMutationPatch",
        name = "Host Mutation Patch",
        drawTab = function() end,
    })

    host.mutation.patch(function(plan, activeHost, activeStore)
        patchHost = activeHost
        patchStore = activeStore
        plan:set(target, "Value", "patched")
    end)

    local ok, err = host.activate()

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(target.Value, "patched")
    lu.assertEquals(patchHost, host)
    lu.assertEquals(patchStore, store)
    lu.assertNil(patchStore.table)
    lu.assertNil(patchStore.getAliasSchema)
end

function TestModuleHost_CreateModule:testHostMutationPatchRejectsAfterActivation()
    local host = self.h.public.createModule({
        pluginGuid = "test-create-module-host-mutation-after-activation",
        config = {},
        id = "HostMutationAfterActivation",
        name = "Host Mutation After Activation",
        drawTab = function() end,
    })
    host.activate()

    lu.assertErrorMsgContains("after host activation", function()
        host.mutation.patch(function() end)
    end)
end

function TestModuleHost_CreateModule:testCreateModuleReturnsErrorAndLogsWarning()
    local host, store, err = self.h.public.createModule({
        pluginGuid = "test-try-create-module-invalid",
        config = {},
        id = "TryCreateInvalid",
        drawTab = function() end,
    })

    lu.assertNil(host)
    lu.assertNil(store)
    lu.assertStrContains(err, "definition.missing_name")
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "host.create_failed")
    lu.assertStrContains(self.h.warnings[1], "definition.missing_name")
    lu.assertNil(self.h:liveHost("test-try-create-module-invalid"))
end

function TestModuleHost_CreateModule:testCreateModuleActivationIsSingleUse()
    local host = self.h.public.createModule({
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
            drawTab = function() end,
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
            drawTab = function() end,
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
            drawTab = function() end,
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleTreatsRegisterIntegrationsAsUnknownOption()
    lu.assertErrorMsgContains("unknown option 'registerIntegrations'", function()
        self.h:createModuleOrThrow({
            pluginGuid = "test-create-module-register-integrations-unknown",
            config = {},
            id = "RegisterIntegrationsUnknown",
            name = "Register Integrations Unknown",
            registerIntegrations = function() end,
            drawTab = function() end,
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
            drawTab = function() end,
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
            drawTab = function() end,
        })
    end)
end

function TestModuleHost_CreateModule:testCreateModuleFingerprintTracksQuickContentPresenceOnly()
    local stableHost = self.h.public.createModule({
        pluginGuid = "test-create-module-quick-content-stable",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentStable",
        name = "Quick Content Stable",
        drawTab = function() end,
        drawQuickContent = function() end,
    })
    stableHost.activate()

    self.h.public.createModule({
        pluginGuid = "test-create-module-quick-content-stable",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentStable",
        name = "Quick Content Stable",
        drawTab = function() end,
        drawQuickContent = function() end,
    })

    lu.assertEquals(#self.h.warnings, 0)

    local addedHost = self.h.public.createModule({
        pluginGuid = "test-create-module-quick-content-added",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentAdded",
        name = "Quick Content Added",
        drawTab = function() end,
    })
    addedHost.activate()

    self.h.public.createModule({
        pluginGuid = "test-create-module-quick-content-added",
        config = {},
        modpack = "create-module-pack",
        id = "QuickContentAdded",
        name = "Quick Content Added",
        drawTab = function() end,
        drawQuickContent = function() end,
    })

    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "structural definition changed during hot reload")
end
