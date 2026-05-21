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
    local drawImgui = nil
    local drawData = nil
    local drawServices = nil
    local drawActions = nil
    local drawWidgets = nil
    local drawNav = nil
    local authorSchemaNode = nil
    local authorDataField = nil
    local authorRowValue = nil
    local authorRootField = nil
    local authorRowField = nil
    local config = {}

    local host, store = self.h.public.createModule({
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
        drawTab = function(draw, data, actions, services)
            drawImgui = draw.imgui
            drawData = data
            drawServices = services
            drawActions = actions
            drawWidgets = draw.widgets
            drawNav = draw.nav
            authorSchemaNode = data.getAliasSchema("Flag")
            authorDataField = data.get("Flag")
            authorRootField = draw.field("Flag")
            local rows = data.get("Rows")
            authorRowField = rows:get(1, "Limit")
            authorRowValue = rows:read(1, "Limit")
            data.write("Flag", true)
        end,
    })

    lu.assertNil(self.h:liveHost("test-create-module"))
    host.activate()
    local liveHost = self.h:liveHost("test-create-module")
    liveHost.drawTab({})

    lu.assertNotNil(drawImgui)
    lu.assertNotNil(drawData)
    lu.assertEquals(drawData, self.h.moduleHost.getState(liveHost).authorSession)
    lu.assertEquals(type(drawServices.log), "function")
    lu.assertEquals(type(drawServices.logIf), "function")
    lu.assertEquals(type(drawServices.isHostEnabled), "function")
    lu.assertEquals(type(drawServices.invokeIntegration), "function")
    lu.assertEquals(type(drawActions.get), "function")
    lu.assertEquals(type(drawActions.hasAny), "function")
    lu.assertEquals(type(drawWidgets.checkbox), "function")
    lu.assertNil(drawWidgets.forSession)
    lu.assertEquals(type(drawNav.verticalTabs), "function")
    lu.assertEquals(type(drawNav.isVisible), "function")
    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(store.read("Flag"), false)
    liveHost.flush()
    lu.assertEquals(store.read("Flag"), true)
    lu.assertEquals(self.h.moduleRuntimeRegistry.getPluginInfo("test-create-module"), {
        pluginGuid = "test-create-module",
        packId = "create-module-pack",
        moduleId = "CreateModule",
        name = "Create Module",
    })
    lu.assertNotNil(authorSchemaNode)
    lu.assertEquals(authorSchemaNode.alias, "Flag")
    lu.assertEquals(authorSchemaNode.type, "bool")
    lu.assertEquals(authorDataField:alias(), "Flag")
    lu.assertEquals(authorDataField:schema().alias, "Flag")
    lu.assertEquals(authorRowValue, 2)
    lu.assertEquals(authorRootField:alias(), "Flag")
    lu.assertEquals(authorRootField:schema().alias, "Flag")
    lu.assertEquals(authorRowField:alias(), "Limit")
    lu.assertEquals(authorRowField:read(), 2)
    local liveState = self.h.moduleHost.getState(liveHost)
    lu.assertEquals(type(liveState.definition._structuralFingerprint), "string")
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
