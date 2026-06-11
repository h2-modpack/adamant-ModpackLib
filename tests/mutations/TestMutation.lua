local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestMutation = {}

local function createModuleState(harness, config, definition)
    return harness:createModuleState(config, definition)
end

function TestMutation:setUp()
    self.harness = createLibHarness()
    self.mutation = self.harness.mutation
    self.mutationPlan = self.harness.mutationPlan
end

function TestMutation:applyPlan(plan)
    return self.mutationPlan.applyPlan(plan)
end

function TestMutation:revertPlan(plan)
    return self.mutationPlan.revertPlan(plan)
end

function TestMutation:testBackupRestoresChangedAndRemovedValues()
    local tbl = {
        Count = 1,
        Nested = { Value = "before" },
    }
    local backup, restore = self.mutationPlan.createBackup()

    backup(tbl, "Count", "Nested", "Missing")
    tbl.Count = 7
    tbl.Nested.Value = "new"
    tbl.Missing = "created"
    restore()

    lu.assertEquals(tbl.Count, 1)
    lu.assertEquals(tbl.Nested, { Value = "before" })
    lu.assertNil(tbl.Missing)
end

function TestMutation:testPlanSetSetManyAndTransformApplyAndRevert()
    local tbl = {
        Count = 1,
        Name = "before",
        Flag = false,
    }
    local plan = self.mutationPlan.createPlan()
        :set(tbl, "Count", 2)
        :setMany(tbl, {
            Name = "new",
            Flag = true,
        })
        :transform(tbl, "Count", function(current)
            return current + 3
        end)

    lu.assertTrue(self:applyPlan(plan))
    lu.assertEquals(tbl, {
        Count = 5,
        Name = "new",
        Flag = true,
    })
    lu.assertFalse(self:applyPlan(plan))
    lu.assertTrue(self:revertPlan(plan))
    lu.assertEquals(tbl, {
        Count = 1,
        Name = "before",
        Flag = false,
    })
    lu.assertFalse(self:revertPlan(plan))
end

function TestMutation:testPlanSetManyClonesInputMapOnDeclaration()
    local tbl = {}
    local values = {
        Name = "new",
        Nested = {
            Value = 1,
        },
    }
    local plan = self.mutationPlan.createPlan()
        :setMany(tbl, values)

    values.Name = "changed"
    values.Nested.Value = 99

    lu.assertTrue(self:applyPlan(plan))
    lu.assertEquals(tbl, {
        Name = "new",
        Nested = {
            Value = 1,
        },
    })
end

function TestMutation:testPlanDoesNotExposeExecutionMethods()
    local plan = self.mutationPlan.createPlan()

    lu.assertNil(plan.apply)
    lu.assertNil(plan.revert)
end

function TestMutation.testPlanExecutorSurvivesLibReload()
    local runtimeRoot = {}
    local first = createLibHarness({ runtime = runtimeRoot })
    local tbl = { Value = "base" }
    local plan = first.mutationPlan.createPlan()
        :set(tbl, "Value", "patched")

    lu.assertTrue(first.mutationPlan.applyPlan(plan))
    lu.assertEquals(tbl.Value, "patched")

    local second = createLibHarness({ runtime = runtimeRoot })

    lu.assertTrue(second.mutationPlan.revertPlan(plan))
    lu.assertEquals(tbl.Value, "base")
end

function TestMutation:testPlanTransformReceivesCopiedCurrentValueOnly()
    local tbl = {
        Data = {
            Count = 1,
        },
    }
    local seenExtraArgCount = nil
    local plan = self.mutationPlan.createPlan()
        :transform(tbl, "Data", function(current, ...)
            seenExtraArgCount = select("#", ...)
            current.Count = current.Count + 1
            return current
        end)

    lu.assertTrue(self:applyPlan(plan))
    lu.assertEquals(seenExtraArgCount, 0)
    lu.assertEquals(tbl.Data, { Count = 2 })
    lu.assertTrue(self:revertPlan(plan))
    lu.assertEquals(tbl.Data, { Count = 1 })
end

function TestMutation:testPlanTransformErrorCannotMutateOriginalCurrentValue()
    local tbl = {
        Data = {
            Count = 1,
        },
    }
    local plan = self.mutationPlan.createPlan()
        :transform(tbl, "Data", function(current)
            current.Count = 999
            error("transform boom")
        end)

    lu.assertErrorMsgContains("transform boom", function()
        self:applyPlan(plan)
    end)
    lu.assertEquals(tbl.Data, { Count = 1 })
end

function TestMutation:testPlanTransformClonesReturnedTable()
    local tbl = {
        Data = {
            Count = 1,
        },
    }
    local replacement = { Count = 2 }
    local plan = self.mutationPlan.createPlan()
        :transform(tbl, "Data", function()
            return replacement
        end)

    lu.assertTrue(self:applyPlan(plan))
    replacement.Count = 999
    lu.assertEquals(tbl.Data, { Count = 2 })
end

function TestMutation:testPlanAppendAndAppendUniqueApplyAndRevert()
    local tbl = {
        Values = { "a" },
        Objects = {
            { id = 1 },
        },
    }
    local plan = self.mutationPlan.createPlan()
        :append(tbl, "Values", "b")
        :appendUnique(tbl, "Values", "a")
        :appendUnique(tbl, "Objects", { id = 1 })
        :appendUnique(tbl, "Objects", { id = 2 })

    lu.assertTrue(self:applyPlan(plan))
    lu.assertEquals(tbl.Values, { "a", "b" })
    lu.assertEquals(tbl.Objects, {
        { id = 1 },
        { id = 2 },
    })
    lu.assertTrue(self:revertPlan(plan))
    lu.assertEquals(tbl.Values, { "a" })
    lu.assertEquals(tbl.Objects, {
        { id = 1 },
    })
end

function TestMutation:testPlanRemoveElementAndSetElementApplyAndRevert()
    local tbl = {
        Values = { "a", "b", "c" },
        Objects = {
            { id = 1, value = "before" },
            { id = 2, value = "keep" },
        },
    }
    local sameId = function(a, b)
        return a.id == b.id
    end
    local plan = self.mutationPlan.createPlan()
        :removeElement(tbl, "Values", "b")
        :setElement(tbl, "Objects", { id = 1 }, { id = 1, value = "new" }, sameId)

    lu.assertTrue(self:applyPlan(plan))
    lu.assertEquals(tbl.Values, { "a", "c" })
    lu.assertEquals(tbl.Objects, {
        { id = 1, value = "new" },
        { id = 2, value = "keep" },
    })
    lu.assertTrue(self:revertPlan(plan))
    lu.assertEquals(tbl.Values, { "a", "b", "c" })
    lu.assertEquals(tbl.Objects, {
        { id = 1, value = "before" },
        { id = 2, value = "keep" },
    })
end

function TestMutation:testPlanListOperationsCreateMissingLists()
    local tbl = {}
    local plan = self.mutationPlan.createPlan()
        :append(tbl, "Values", "a")
        :appendUnique(tbl, "Objects", { id = 1 })

    lu.assertTrue(self:applyPlan(plan))
    lu.assertEquals(tbl.Values, { "a" })
    lu.assertEquals(tbl.Objects, { { id = 1 } })
    lu.assertTrue(self:revertPlan(plan))
    lu.assertNil(tbl.Values)
    lu.assertNil(tbl.Objects)
end

function TestMutation:testPlanListOperationsRejectNonTableTargets()
    local tbl = {
        Values = "not-list",
    }

    lu.assertErrorMsgContains("append requires table", function()
        local plan = self.mutationPlan.createPlan()
            :append(tbl, "Values", "a")
        self:applyPlan(plan)
    end)

    lu.assertErrorMsgContains("removeElement requires table", function()
        local plan = self.mutationPlan.createPlan()
            :removeElement(tbl, "Values", "a")
        self:applyPlan(plan)
    end)

    lu.assertErrorMsgContains("setElement requires table", function()
        local plan = self.mutationPlan.createPlan()
            :setElement(tbl, "Values", "a", "b")
        self:applyPlan(plan)
    end)
end

function TestMutation:testPlanApplyRestoresEarlierMutationsWhenLaterOperationFails()
    local tbl = {
        Count = 1,
        Values = "not-list",
    }
    local plan = self.mutationPlan.createPlan()
        :set(tbl, "Count", 2)
        :append(tbl, "Values", "a")

    lu.assertErrorMsgContains("append requires table", function()
        self:applyPlan(plan)
    end)

    lu.assertEquals(tbl, {
        Count = 1,
        Values = "not-list",
    })
    lu.assertFalse(self:revertPlan(plan))
end

function TestMutation:testPlanReapplyAfterRevertCapturesFreshSnapshot()
    local tbl = {
        Count = 1,
    }
    local plan = self.mutationPlan.createPlan()
        :set(tbl, "Count", 2)

    lu.assertTrue(self:applyPlan(plan))
    lu.assertEquals(tbl.Count, 2)
    lu.assertTrue(self:revertPlan(plan))
    lu.assertEquals(tbl.Count, 1)

    tbl.Count = 5

    lu.assertTrue(self:applyPlan(plan))
    lu.assertEquals(tbl.Count, 2)
    lu.assertTrue(self:revertPlan(plan))
    lu.assertEquals(tbl.Count, 5)
end

function TestMutation:testFailedPlanRetryRestoresToLatestSnapshot()
    local tbl = {
        Count = 1,
        Values = "not-list",
    }
    local plan = self.mutationPlan.createPlan()
        :set(tbl, "Count", 2)
        :append(tbl, "Values", "a")

    lu.assertErrorMsgContains("append requires table", function()
        self:applyPlan(plan)
    end)
    lu.assertEquals(tbl.Count, 1)

    tbl.Count = 4

    lu.assertErrorMsgContains("append requires table", function()
        self:applyPlan(plan)
    end)
    lu.assertEquals(tbl, {
        Count = 4,
        Values = "not-list",
    })
end

function TestMutation:testCommittedNoopSyncReceiptDisposesSuccessfully()
    local definition = self.harness.managedModule.prepareDefinition({}, {
        id = "NoopMutationReceipt",
        name = "Noop Mutation Receipt",
        storage = {},
    })
    local store, stagedState = createModuleState(self.harness, {
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = self.harness.managedModule.create({
        pluginGuid = "test-noop-mutation-receipt",
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
    })
    local receipt = self.mutation.syncForModule(host)

    local ok, err = receipt.commit()
    lu.assertTrue(ok, tostring(err))

    ok, err = receipt.dispose()
    lu.assertTrue(ok, tostring(err))
end
