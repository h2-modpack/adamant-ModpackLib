local lu = require('luaunit')

TestDefinitionLifecycle = {}

function TestDefinitionLifecycle:testSetApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { HP = 100 }

    plan:set(tbl, "HP", 250)

    lu.assertTrue(plan:apply())
    lu.assertEquals(tbl.HP, 250)
    lu.assertTrue(plan.revert())
    lu.assertEquals(tbl.HP, 100)
end

function TestDefinitionLifecycle:testSetClonesTableValue()
    local plan = lib.mutation.createPlan()
    local replacement = { Damage = 100 }
    local tbl = { Data = { Damage = 10 } }

    plan:set(tbl, "Data", replacement)
    plan:apply()
    replacement.Damage = 999

    lu.assertEquals(tbl.Data.Damage, 100)
    plan:revert()
    lu.assertEquals(tbl.Data.Damage, 10)
end

function TestDefinitionLifecycle:testSetManyApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { A = 1, B = 2, C = 3 }

    plan:setMany(tbl, { A = 10, B = 20 })
    plan:apply()

    lu.assertEquals(tbl.A, 10)
    lu.assertEquals(tbl.B, 20)
    lu.assertEquals(tbl.C, 3)

    plan:revert()
    lu.assertEquals(tbl.A, 1)
    lu.assertEquals(tbl.B, 2)
    lu.assertEquals(tbl.C, 3)
end

function TestDefinitionLifecycle:testTransformApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { Requirements = { "A" } }

    plan:transform(tbl, "Requirements", function(current)
        local nextValue = rom.game.DeepCopyTable(current)
        table.insert(nextValue, "B")
        return nextValue
    end)

    plan:apply()
    lu.assertEquals(tbl.Requirements, { "A", "B" })

    plan:revert()
    lu.assertEquals(tbl.Requirements, { "A" })
end

function TestDefinitionLifecycle:testAppendCreatesMissingListAndRestoresNil()
    local plan = lib.mutation.createPlan()
    local tbl = {}

    plan:append(tbl, "Values", "A")
    plan:apply()

    lu.assertEquals(tbl.Values, { "A" })

    plan:revert()
    lu.assertNil(tbl.Values)
end

function TestDefinitionLifecycle:testAppendUniqueUsesDeepEquivalenceByDefault()
    local plan = lib.mutation.createPlan()
    local tbl = {
        Requirements = {
            { Path = { "CurrentRun", "Hero" }, Value = 1 },
        },
    }

    plan:appendUnique(tbl, "Requirements", { Path = { "CurrentRun", "Hero" }, Value = 1 })
    plan:apply()

    lu.assertEquals(#tbl.Requirements, 1)
    plan:revert()
    lu.assertEquals(#tbl.Requirements, 1)
end

function TestDefinitionLifecycle:testAppendUniqueCanUseCustomComparator()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { { Name = "A", Count = 1 } } }

    plan:appendUnique(tbl, "Values", { Name = "A", Count = 2 }, function(a, b)
        return a.Name == b.Name
    end)
    plan:apply()

    lu.assertEquals(#tbl.Values, 1)
end

function TestDefinitionLifecycle:testApplyAndRevertAreRepeatSafe()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = {} }

    plan:append(tbl, "Values", "A")
    lu.assertTrue(plan:apply())
    lu.assertFalse(plan:apply())
    lu.assertEquals(tbl.Values, { "A" })

    lu.assertTrue(plan:revert())
    lu.assertFalse(plan:revert())
    lu.assertEquals(tbl.Values, {})
end

function TestDefinitionLifecycle:testAppendErrorsOnNonTableTarget()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = 5 }

    plan:append(tbl, "Values", "A")
    lu.assertError(plan.apply)
end

function TestDefinitionLifecycle:testAppendUniqueDoesNotAliasInsertedTable()
    local plan = lib.mutation.createPlan()
    local entry = { Name = "A", Meta = { Count = 1 } }
    local tbl = { Values = {} }

    plan:appendUnique(tbl, "Values", entry)
    plan:apply()
    entry.Meta.Count = 999

    lu.assertEquals(tbl.Values[1].Meta.Count, 1)
end

function TestDefinitionLifecycle:testRemoveElementApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { "A", "B", "C" } }

    plan:removeElement(tbl, "Values", "B")
    plan:apply()

    lu.assertEquals(tbl.Values, { "A", "C" })

    plan:revert()
    lu.assertEquals(tbl.Values, { "A", "B", "C" })
end

function TestDefinitionLifecycle:testRemoveElementCanUseCustomComparator()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { { Name = "A", Count = 1 }, { Name = "B", Count = 2 } } }

    plan:removeElement(tbl, "Values", { Name = "A", Count = 999 }, function(a, b)
        return a.Name == b.Name
    end)
    plan:apply()

    lu.assertEquals(#tbl.Values, 1)
    lu.assertEquals(tbl.Values[1].Name, "B")
end

function TestDefinitionLifecycle:testSetElementApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { "A", "B", "C" } }

    plan:setElement(tbl, "Values", "B", "Z")
    plan:apply()

    lu.assertEquals(tbl.Values, { "A", "Z", "C" })

    plan:revert()
    lu.assertEquals(tbl.Values, { "A", "B", "C" })
end

function TestDefinitionLifecycle:testSetElementClonesReplacementTable()
    local plan = lib.mutation.createPlan()
    local replacement = { Name = "Z", Meta = { Count = 10 } }
    local tbl = { Values = { { Name = "A" }, { Name = "B" } } }

    plan:setElement(tbl, "Values", { Name = "B" }, replacement, function(a, b)
        return a.Name == b.Name
    end)
    plan:apply()
    replacement.Meta.Count = 999

    lu.assertEquals(tbl.Values[2].Name, "Z")
    lu.assertEquals(tbl.Values[2].Meta.Count, 10)
end

function TestDefinitionLifecycle:testRemoveElementErrorsOnNonTableTarget()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = 5 }

    plan:removeElement(tbl, "Values", "A")
    lu.assertError(plan.apply)
end

function TestDefinitionLifecycle:testSetElementErrorsOnNonTableTarget()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = 5 }

    plan:setElement(tbl, "Values", "A", "B")
    lu.assertError(plan.apply)
end

function TestDefinitionLifecycle:testInferMutationShapeManual()
    local mode, info = lib.mutation.inferShape({
        apply = function() end,
        revert = function() end,
    })

    lu.assertEquals(mode, "manual")
    lu.assertTrue(info.hasManual)
    lu.assertFalse(info.hasPatch)
end

function TestDefinitionLifecycle:testInferMutationShapePatch()
    local mode, info = lib.mutation.inferShape({
        patchPlan = function() end,
    })

    lu.assertEquals(mode, "patch")
    lu.assertTrue(info.hasPatch)
    lu.assertFalse(info.hasManual)
end

function TestDefinitionLifecycle:testInferMutationShapeHybrid()
    local mode, info = lib.mutation.inferShape({
        patchPlan = function() end,
        apply = function() end,
        revert = function() end,
    })

    lu.assertEquals(mode, "hybrid")
    lu.assertTrue(info.hasPatch)
    lu.assertTrue(info.hasManual)
end

function TestDefinitionLifecycle:testAffectsRunDataIgnoresDeprecatedFlag()
    lu.assertTrue(lib.mutation.mutatesRunData({ affectsRunData = true }))
    lu.assertFalse(lib.mutation.mutatesRunData({ affectsRunData = false }))
    lu.assertFalse(lib.mutation.mutatesRunData({ dataMutation = true }))
    lu.assertFalse(lib.mutation.mutatesRunData({}))
end

function TestDefinitionLifecycle:testApplyDefinitionSupportsPatchOnly()
    local store = lib.store.create({ Enabled = false }, { storage = {} })
    local target = { Value = 1 }
    local def = {
        patchPlan = function(plan)
            plan:set(target, "Value", 7)
        end,
    }

    local ok, err = lib.mutation.apply(def, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 7)

    ok, err = lib.mutation.revert(def, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)
end

function TestDefinitionLifecycle:testApplyDefinitionNoOpsWhenLifecycleMissingAndRunDataUnaffected()
    local store = lib.store.create({ Enabled = false }, { storage = {} })
    local def = {
        affectsRunData = false,
    }

    local ok, err = lib.mutation.apply(def, store)
    lu.assertTrue(ok)
    lu.assertNil(err)

    ok, err = lib.mutation.revert(def, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
end

function TestDefinitionLifecycle:testSetDefinitionEnabledCommitsOnlyAfterSuccessfulEnable()
    local store = lib.store.create({ Enabled = false }, { storage = {} })
    local applied = false
    local def = {
        apply = function()
            applied = true
        end,
        revert = function() end,
    }

    local ok, err = lib.mutation.setEnabled(def, store, true)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertTrue(applied)
    lu.assertTrue(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledDoesNotCommitFailedEnable()
    local store = lib.store.create({ Enabled = false }, { storage = {} })
    local def = {
        apply = function()
            error("enable boom")
        end,
        revert = function() end,
    }

    local ok, err = lib.mutation.setEnabled(def, store, true)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "enable boom")
    lu.assertFalse(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledDoesNotCommitFailedDisable()
    local store = lib.store.create({ Enabled = true }, { storage = {} })
    local def = {
        apply = function() end,
        revert = function()
            error("disable boom")
        end,
    }

    local ok, err = lib.mutation.setEnabled(def, store, false)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "disable boom")
    lu.assertTrue(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledReappliesWhenAlreadyEnabled()
    local store = lib.store.create({ Enabled = true }, { storage = {} })
    local calls = {}
    local def = {
        apply = function()
            table.insert(calls, "apply")
        end,
        revert = function()
            table.insert(calls, "revert")
        end,
    }

    local ok, err = lib.mutation.setEnabled(def, store, true)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, { "revert", "apply" })
    lu.assertTrue(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledNoOpsWhenAlreadyDisabled()
    local store = lib.store.create({ Enabled = false }, { storage = {} })
    local revertCalls = 0
    local def = {
        apply = function() end,
        revert = function()
            revertCalls = revertCalls + 1
        end,
    }

    local ok, err = lib.mutation.setEnabled(def, store, false)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(revertCalls, 0)
    lu.assertFalse(store.read("Enabled"))
end

function TestDefinitionLifecycle:testReapplyDefinitionStopsWhenRevertFails()
    local store = lib.store.create({ Enabled = true }, { storage = {} })
    local applyCalls = 0
    local def = {
        apply = function()
            applyCalls = applyCalls + 1
        end,
        revert = function()
            error("revert boom")
        end,
    }

    local ok, err = lib.mutation.reapply(def, store)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "revert boom")
    lu.assertEquals(applyCalls, 0)
end

function TestDefinitionLifecycle:testHybridOrderingIsPatchThenManualOnApplyAndManualThenPatchOnRevert()
    local store = lib.store.create({ Enabled = false }, { storage = {} })
    local target = { Value = 0 }
    local order = {}
    local def = {
        patchPlan = function(plan)
            table.insert(order, "build")
            plan:set(target, "Value", 10)
        end,
        apply = function()
            table.insert(order, "manual-apply")
            target.Value = target.Value + 5
        end,
        revert = function()
            table.insert(order, "manual-revert")
            target.Value = -1
        end,
    }

    local ok = lib.mutation.apply(def, store)
    lu.assertTrue(ok)
    lu.assertEquals(order, { "build", "manual-apply" })
    lu.assertEquals(target.Value, 15)

    ok = lib.mutation.revert(def, store)
    lu.assertTrue(ok)
    lu.assertEquals(order, { "build", "manual-apply", "manual-revert" })
    lu.assertEquals(target.Value, 0)
end
