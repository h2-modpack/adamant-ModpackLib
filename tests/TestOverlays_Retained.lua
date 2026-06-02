local lu = require("luaunit")
local createOverlayHarness = require("tests/harness/create_overlay_harness")

TestOverlays_Retained = {}

function TestOverlays_Retained:setUp()
    self.h = createOverlayHarness()
end

function TestOverlays_Retained:tearDown()
    if self.restoreWarnings then
        self.restoreWarnings()
        self.restoreWarnings = nil
    end
end

function TestOverlays_Retained:captureWarnings()
    local warnings = {}
    local previousPrint = self.h.harness.env.print
    self.h.config.DebugMode = true
    self.h.harness.env.print = function(msg)
        warnings[#warnings + 1] = msg
    end
    self.restoreWarnings = function()
        self.h.config.DebugMode = false
        self.h.harness.env.print = previousPrint
    end
    return warnings
end

function TestOverlays_Retained:createHostWithOverlays(pluginGuid, declareOverlays, opts)
    return self.h.createHostWithOverlays(pluginGuid, declareOverlays, opts)
end

function TestOverlays_Retained:testSystemOverlayLineProjectsThroughCommitContext()
    local modified = {}
    self.h.game.modifyTextBox = function(args)
        modified[#modified + 1] = args
    end

    self.h.createSystem("test.retained.line").overlays.define(function(overlays)
        overlays.createLine("summary.igt", {
            region = "middleRightStack",
            columns = {
                { key = "label", minWidth = 40 },
                { key = "time", minWidth = 80 },
            },
        })
        overlays.onCommit(function(overlay)
            overlay.setLine("summary.igt", { label = "IGT:", time = "01:23.45" })
            overlay.refresh("summary.igt")
        end)
    end)

    self.h.overlays.dispatchCommit("test.retained.line", {})

    lu.assertEquals(modified[#modified - 1].Text, "IGT:")
    lu.assertEquals(modified[#modified].Text, "01:23.45")
end

function TestOverlays_Retained:testSystemOverlayDefineRemovesOmittedDeclarations()
    local destroyed = {}
    self.h.game.destroy = function(args)
        destroyed[#destroyed + 1] = args.Id
    end

    local system = self.h.createSystem("test.retained.omit")
    system.overlays.define(function(overlays)
        overlays.createLine("transient", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end)
    lu.assertNotNil(next(self.h.rendererState.textElements))

    system.overlays.define(function() end)

    lu.assertNil(next(self.h.rendererState.stackRows))
    lu.assertNil(next(self.h.rendererState.textElements))
    lu.assertTrue(#destroyed > 0)
end

function TestOverlays_Retained:testRetainedTableCapsRowsAndHidesUnusedRows()
    local modified = {}
    local alphas = {}
    self.h.game.modifyTextBox = function(args)
        modified[#modified + 1] = args
    end
    self.h.game.setAlpha = function(args)
        alphas[#alphas + 1] = args
    end

    local host, authorModule = self:createHostWithOverlays("test.retained.table", function(overlays)
        overlays.createTable("runs", {
            region = "middleRightStack",
            maxRows = 2,
            columns = {
                { key = "label", minWidth = 40 },
                { key = "time", minWidth = 80 },
            },
        })
        overlays.onCommit(function(_, _, overlay)
            overlay.setTable("runs", {
                { key = "one", label = "Run 1", time = "00:01.00" },
                { key = "two", label = "Run 2", time = "00:02.00" },
                { key = "three", label = "Run 3", time = "00:03.00" },
            })
            overlay.refresh("runs")
        end)
    end)
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))
    self.h.overlays.dispatchCommit(host, {})

    local text = {}
    for _, call in ipairs(modified) do
        text[call.Text] = true
    end
    lu.assertTrue(text["Run 1"])
    lu.assertTrue(text["00:01.00"])
    lu.assertTrue(text["Run 2"])
    lu.assertTrue(text["00:02.00"])
    lu.assertNil(text["Run 3"])
    lu.assertNil(text["00:03.00"])
    lu.assertTrue(#alphas > 0)
end

function TestOverlays_Retained:testHostOverlayCallbacksReceiveStandardRuntimeShape()
    local seen = nil
    local host, authorModule = self:createHostWithOverlays("test.retained.standard-shape", function(overlays)
        overlays.createLine("line", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
        overlays.onCommit(function(callbackHost, runtime, overlay, commit)
            overlay.setLine("line", runtime.data.read("Flag") and "enabled" or "disabled")
            seen = {
                hostId = callbackHost.getHostId(),
                hasLifecycleSetEnabled = type(callbackHost.setEnabled) == "function",
                runtimeValue = runtime.data.read("Flag"),
                commitValue = commit.reason,
            }
        end)
    end, {
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        config = {
            Enabled = true,
            DebugMode = false,
            Flag = true,
        },
    })
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))

    self.h.overlays.dispatchCommit(host, { reason = "test" })

    lu.assertEquals(seen, {
        hostId = host.getHostId(),
        hasLifecycleSetEnabled = false,
        runtimeValue = true,
        commitValue = "test",
    })
end

function TestOverlays_Retained:testHostOverlayVisibilityReceivesStandardRuntimeShape()
    local lineSeen = nil
    local columnSeen = nil
    local host, authorModule = self:createHostWithOverlays("test.retained.visibility-shape", function(overlays)
        overlays.createLine("line", {
            region = "middleRightStack",
            visible = function(callbackHost, runtime)
                lineSeen = {
                    hostId = callbackHost.getHostId(),
                    runtimeValue = runtime.data.read("Flag"),
                }
                return runtime.data.read("Flag") == true
            end,
            columns = {
                {
                    key = "text",
                    minWidth = 40,
                    visible = function(callbackHost, runtime)
                        columnSeen = {
                            hostId = callbackHost.getHostId(),
                            runtimeValue = runtime.data.read("Flag"),
                        }
                        return runtime.data.read("Flag") == true
                    end,
                },
            },
        })
    end, {
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        config = {
            Enabled = true,
            DebugMode = false,
            Flag = true,
        },
    })
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))

    lu.assertEquals(lineSeen, {
        hostId = host.getHostId(),
        runtimeValue = true,
    })
    lu.assertEquals(columnSeen, lineSeen)
end

function TestOverlays_Retained:testRetainedTableRequiresPositiveMaxRows()
    lu.assertErrorMsgContains("maxRows must be a positive integer", function()
        self:createHostWithOverlays("test.retained.table.invalid", function(overlays)
            overlays.createTable("runs", {
                region = "middleRightStack",
                columns = {
                    { key = "label", minWidth = 40 },
                },
            })
        end)
    end)
end

function TestOverlays_Retained:testHostOverlayDeclarationsRejectAfterActivation()
    local authorModule = self.h.public.createModule({
        pluginGuid = "test.retained.after-activation",
        config = {
            Enabled = true,
            DebugMode = false,
        },
        id = "OverlayHost",
        name = "Overlay Host",
    })
    authorModule.overlays.createLine("line", {
        region = "middleRightStack",
        columns = {
            { key = "text", minWidth = 40 },
        },
    })
    authorModule.ui.tab(function() end)
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))

    lu.assertErrorMsgContains("cannot be called after module activation begins", function()
        authorModule.overlays.createLine("late", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end)
end

function TestOverlays_Retained:testHostOverlayDeclarationsAreStoredOnModuleRegistry()
    local host = self:createHostWithOverlays("test.retained.state-declarations", function(overlays)
        overlays.createLine("line", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end)

    local record = self.h.harness.moduleRegistry.getRecord(host)
    lu.assertNotNil(record.overlayDeclarations)
    lu.assertEquals(record.overlayDeclarations.entries[1].kind, "createLine")
    lu.assertEquals(record.overlayDeclarations.entries[1].name, "line")
end

function TestOverlays_Retained:testSystemOverlayProjectionDoesNotExposeOwner()
    local exposedOwner = nil
    self.h.createSystem("test.retained.no-owner").overlays.define(function(overlays)
        overlays.createLine("line", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
        overlays.onCommit(function(overlay)
            exposedOwner = overlay.owner
        end)
    end)

    self.h.overlays.dispatchCommit("test.retained.no-owner", {})

    lu.assertNil(exposedOwner)
end

function TestOverlays_Retained:testHostCommitDispatchesOverlaysAfterSettingsObserver()
    local pluginGuid = "test-retained-overlay-commit"
    local order = {}
    local host, authorModule, _, stagedState = self:createHostWithOverlays(pluginGuid, function(overlays)
        overlays.onCommit(function()
            order[#order + 1] = "overlay"
        end)
    end, {
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        config = {
            Enabled = true,
            DebugMode = false,
            Flag = false,
        },
        onCommit = function()
            order[#order + 1] = "commit"
        end,
    })
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))

    stagedState.write("Flag", true)
    ok, err = host.flush()

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(order, { "commit", "overlay" })
end

function TestOverlays_Retained:testHostCommitDispatchesOverlaysWhenSettingsObserverFails()
    local warnings = self:captureWarnings()
    local pluginGuid = "test-retained-overlay-commit-observer-failure"
    local order = {}
    local host, authorModule, _, stagedState = self:createHostWithOverlays(pluginGuid, function(overlays)
        overlays.onCommit(function()
            order[#order + 1] = "overlay"
        end)
    end, {
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        config = {
            Enabled = true,
            DebugMode = false,
            Flag = false,
        },
        onCommit = function()
            order[#order + 1] = "commit"
            error("commit observer boom")
        end,
    })
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))

    stagedState.write("Flag", true)
    ok, err = host.flush()

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(err)
    lu.assertEquals(order, { "commit", "overlay" })
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "lifecycle.on_commit_failed")
    lu.assertStrContains(warnings[1], "commit observer boom")
end

function TestOverlays_Retained:testHostInstallStagesOverlayRowsHiddenUntilCommit()
    local pluginGuid = "test-retained-overlay-staging"
    local ownerId = pluginGuid
    local host, _, store = self:createHostWithOverlays(pluginGuid, function(overlays)
        overlays.createLine("candidate", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end)
    local pendingRowKey = "middleRightStack\0" .. ownerId .. ":pending:candidate"
    local currentRowKey = "middleRightStack\0" .. ownerId .. ":current:candidate"

    local receipt = self.h.overlays.installForModule(host, store)

    lu.assertNil(self.h.rendererState.stackRows[currentRowKey])
    lu.assertNotNil(self.h.rendererState.stackRows[pendingRowKey])
    local stagedRows = 0
    for _, row in pairs(self.h.rendererState.stackRows) do
        stagedRows = stagedRows + 1
        lu.assertFalse(row.visible())
    end
    lu.assertTrue(stagedRows > 0)

    local ok, err = receipt.commit()

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(self.h.rendererState.stackRows[pendingRowKey])
    lu.assertNotNil(self.h.rendererState.stackRows[currentRowKey])
    lu.assertTrue(self.h.rendererState.stackRows[currentRowKey].visible())

    ok, err = receipt.dispose()

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(self.h.rendererState.stackRows[currentRowKey])
end

function TestOverlays_Retained:testHotReloadSameOverlayNameSurvivesOldHostRetirement()
    local pluginGuid = "test-retained-overlay-same-name-reload"
    local ownerId = pluginGuid
    local rowKey = "middleRightStack\0" .. ownerId .. ":current:shared"
    local firstHost, firstAuthorModule = self:createHostWithOverlays(pluginGuid, function(overlays)
        overlays.createLine("shared", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end, {
        id = "RetainedSameNameReload",
    })
    local ok, err = firstAuthorModule.activate()
    lu.assertTrue(ok, tostring(err))

    local firstRow = self.h.rendererState.stackRows[rowKey]
    lu.assertNotNil(firstRow)

    local secondHost, secondAuthorModule = self:createHostWithOverlays(pluginGuid, function(overlays)
        overlays.createLine("shared", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end, {
        id = "RetainedSameNameReload",
    })
    ok, err = secondAuthorModule.activate()
    lu.assertTrue(ok, tostring(err))

    local secondRow = self.h.rendererState.stackRows[rowKey]
    local firstRegistry = self.h.retainedState.tableRegistries[firstHost]
    local secondRegistry = self.h.retainedState.tableRegistries[secondHost]

    lu.assertEquals(self.h.harness.moduleHost.getLiveModule(pluginGuid), secondHost)
    lu.assertNotNil(secondRow)
    lu.assertNotEquals(firstRow, secondRow)
    lu.assertTrue(firstRegistry == nil or firstRegistry.elements.shared == nil)
    lu.assertNotNil(secondRegistry.elements.shared)
end

function TestOverlays_Retained:testRetainedIntervalDispatchesWhenDue()
    local calls = 0
    local _, authorModule = self:createHostWithOverlays("test.retained.interval", function(overlays)
        overlays.onInterval("tick", 1.0, function()
            calls = calls + 1
        end)
    end)
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))

    self.h.overlays.dispatchIntervals(0)
    self.h.overlays.dispatchIntervals(0.5)
    self.h.overlays.dispatchIntervals(1.1)

    lu.assertEquals(calls, 2)
end

function TestOverlays_Retained:testHostIntervalPredicateReceivesEndpointContext()
    local calls = 0
    local seen = nil
    local callbackEvent = nil
    local host, authorModule
    host, authorModule = self:createHostWithOverlays("test.retained.interval.when-context", function(overlays)
        overlays.onInterval("tick", 1.0, function(callbackHost, runtime, _, event)
            calls = calls + 1
            callbackEvent = {
                hostId = callbackHost.getHostId(),
                runtimeValue = runtime.data.read("Flag"),
                name = event.name,
                now = event.now,
            }
        end, {
            when = function(callbackHost, runtime, event)
                seen = {
                    hostId = callbackHost.getHostId(),
                    runtimeValue = runtime.data.read("Flag"),
                    name = event.name,
                    now = event.now,
                }
                return callbackHost.getHostId() == host.getHostId() and runtime.data.read("Flag") == true
            end,
        })
    end, {
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        config = {
            Enabled = true,
            DebugMode = false,
            Flag = true,
        },
    })
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))

    self.h.overlays.dispatchIntervals(2.5)

    lu.assertEquals(calls, 1)
    lu.assertEquals(seen, {
        hostId = host.getHostId(),
        runtimeValue = true,
        name = "tick",
        now = 2.5,
    })
    lu.assertEquals(callbackEvent, seen)
end

function TestOverlays_Retained.testRetainedIntervalDriverUsesInjectedRom()
    local alwaysDrawCallbacks = {}
    local h = createOverlayHarness({
        rom = {
            gui = {
                add_always_draw_imgui = function(callback)
                    alwaysDrawCallbacks[#alwaysDrawCallbacks + 1] = callback
                end,
            },
        },
    })
    h.harness.env.rom = {
        gui = {
            add_always_draw_imgui = function()
                error("global rom used")
            end,
        },
    }
    local baselineCallbacks = #alwaysDrawCallbacks
    local calls = 0
    local _, authorModule = h.createHostWithOverlays("test.retained.interval.driver", function(overlays)
        overlays.onInterval("tick", 1.0, function()
            calls = calls + 1
        end)
    end)
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))

    lu.assertEquals(#alwaysDrawCallbacks, baselineCallbacks + 1)
    alwaysDrawCallbacks[#alwaysDrawCallbacks]()
    lu.assertEquals(calls, 1)
end

function TestOverlays_Retained:testExplicitOwnerIntervalPredicateRunsOncePerDispatch()
    local whenCalls = 0
    local _, authorModule = self:createHostWithOverlays("test.retained.interval.once", function(overlays)
        overlays.onInterval("tick", 1.0, function() end, {
            when = function()
                whenCalls = whenCalls + 1
                return true
            end,
        })
    end)
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))

    self.h.overlays.dispatchIntervals(0)

    lu.assertEquals(whenCalls, 1)
end

function TestOverlays_Retained:testAfterHookObservesResultsWithoutChangingReturn()
    local wrapped = nil
    local observed = nil
    self.h.modutil.Path.Wrap = function(path, handler)
        lu.assertEquals(path, "StartNewRunAfter")
        wrapped = handler
    end

    local pluginGuid = "test-retained-overlay-after-hook"
    local _, authorModule = self:createHostWithOverlays(pluginGuid, function(overlays)
        overlays.afterHook("StartNewRunAfter", function(_, _, _, event)
            observed = {
                arg = event.args[1],
                result = event.result,
            }
        end)
    end)
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))

    local result = wrapped(function(value)
        return value .. ":base"
    end, "run")

    lu.assertEquals(result, "run:base")
    lu.assertEquals(observed, {
        arg = "run",
        result = "run:base",
    })
end

function TestOverlays_Retained:testAfterHookPreservesNilResultArity()
    local wrapped = nil
    local observed = nil
    self.h.modutil.Path.Wrap = function(path, handler)
        lu.assertEquals(path, "StartNewRunNilResults")
        wrapped = handler
    end

    local _, authorModule = self:createHostWithOverlays("test-retained-overlay-after-hook-nil-results", function(overlays)
        overlays.afterHook("StartNewRunNilResults", function(_, _, _, event)
            observed = event.results
        end)
    end)
    local ok, err = authorModule.activate()
    lu.assertTrue(ok, tostring(err))

    local first, second, third = wrapped(function()
        return nil, "second", nil
    end)

    lu.assertNil(first)
    lu.assertEquals(second, "second")
    lu.assertNil(third)
    lu.assertEquals(observed.n, 3)
    lu.assertNil(observed[1])
    lu.assertEquals(observed[2], "second")
    lu.assertNil(observed[3])
end

function TestOverlays_Retained:testSystemOverlayDoesNotExposeHookOrIntervalEvents()
    self.h.createSystem("test.retained.system.surface").overlays.define(function(overlays)
        lu.assertNil(overlays.afterHook)
        lu.assertNil(overlays.onInterval)
        lu.assertNil(overlays.createTable)
    end)
end

function TestOverlays_Retained:testHostAfterHookIsRemovedWhenOmitted()
    local wrapped = nil
    local wrapCalls = 0
    local observed = false
    local pluginGuid = "test-retained-host-after-omit"
    self.h.modutil.Path.Wrap = function(path, handler)
        lu.assertEquals(path, "StartNewRunOmit")
        wrapCalls = wrapCalls + 1
        wrapped = handler
    end

    local _, firstAuthorModule = self:createHostWithOverlays(pluginGuid, function(overlays)
        overlays.afterHook("StartNewRunOmit", function()
            observed = true
        end)
    end)
    local ok, err = firstAuthorModule.activate()
    lu.assertTrue(ok, tostring(err))

    local _, secondAuthorModule = self:createHostWithOverlays(pluginGuid, function() end)
    ok, err = secondAuthorModule.activate()
    lu.assertTrue(ok, tostring(err))

    local result = wrapped(function(value)
        return value .. ":base"
    end, "run")

    lu.assertEquals(wrapCalls, 1)
    lu.assertEquals(result, "run:base")
    lu.assertFalse(observed)
end

function TestOverlays_Retained:testHostAfterHookRollsBackOnActivationFailure()
    local wrapped = nil
    local observed = nil
    local pluginGuid = "test-retained-host-after-rollback"
    self.h.modutil.Path.Wrap = function(path, handler)
        lu.assertEquals(path, "StartNewRunRollback")
        wrapped = handler
    end

    local _, firstAuthorModule = self:createHostWithOverlays(pluginGuid, function(overlays)
        overlays.afterHook("StartNewRunRollback", function()
            observed = "first"
        end)
    end)
    local ok, err = firstAuthorModule.activate()
    lu.assertTrue(ok, tostring(err))

    local _, secondAuthorModule = self:createHostWithOverlays(pluginGuid, function(overlays)
        overlays.afterHook("StartNewRunRollback", function()
            observed = "second"
        end)
    end, {
        patchMutation = function()
            error("rollback after overlay hook")
        end,
    })
    ok, err = secondAuthorModule.activate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "rollback after overlay hook")

    wrapped(function(value)
        return value .. ":base"
    end, "run")

    lu.assertEquals(observed, "first")
end

function TestOverlays_Retained:testActivationFailureRollsBackOverlayDeclarations()
    local pluginGuid = "test-retained-rollback"
    local firstHost, firstAuthorModule = self:createHostWithOverlays(pluginGuid, function(overlays)
        overlays.createLine("stable", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end, {
        id = "RetainedRollback",
    })
    local ok, err = firstAuthorModule.activate()
    lu.assertTrue(ok, tostring(err))

    local _, secondAuthorModule = self:createHostWithOverlays(pluginGuid, function(overlays)
        overlays.createLine("replacement", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end, {
        id = "RetainedRollback",
        patchMutation = function()
            error("rollback after overlays")
        end,
    })

    ok, err = secondAuthorModule.activate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "rollback after overlays")
    local retained = self.h.retainedState.tableRegistries[firstHost]
    lu.assertNotNil(retained.elements.stable)
    lu.assertNil(retained.elements.replacement)
    lu.assertEquals(self.h.harness.moduleHost.getLiveModule(pluginGuid), firstHost)
end
