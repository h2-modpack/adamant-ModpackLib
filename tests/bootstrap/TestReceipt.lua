local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestReceipt = {}

function TestReceipt:setUp()
    self.receipt = createLibHarness().receipt
    self.calls = {}
end

function TestReceipt:recorder(label, result, err)
    return function()
        self.calls[#self.calls + 1] = label
        if result == "raise" then
            error(err, 0)
        end
        if result == false then
            return false, err
        end
        return true, nil
    end
end

function TestReceipt:createRecording(name, opts)
    opts = opts or {}
    return self.receipt.create({
        name = name,
        phase = opts.phase or self.receipt.PHASE_EFFECTS,
        commit = self:recorder(name .. ":commit", opts.commitResult, opts.commitErr),
        rollback = self:recorder(name .. ":rollback", opts.rollbackResult, opts.rollbackErr),
        retire = self:recorder(name .. ":retire", opts.retireResult, opts.retireErr),
        discard = opts.discard and self:recorder(name .. ":discard") or nil,
    })
end

function TestReceipt:testCreateExposesNameAndPhase()
    local receipt = self:createRecording("a", { phase = self.receipt.PHASE_GAME_DATA })

    lu.assertEquals(receipt.name, "a")
    lu.assertEquals(receipt.phase, self.receipt.PHASE_GAME_DATA)
    lu.assertTrue(self.receipt.PHASE_GAME_DATA < self.receipt.PHASE_EFFECTS)
end

function TestReceipt:testCommitRunsOnce()
    local receipt = self:createRecording("a")

    lu.assertTrue(receipt.commit())
    lu.assertTrue(receipt.commit())

    lu.assertEquals(self.calls, { "a:commit" })
end

function TestReceipt:testCommitReportsReturnedAndRaisedFailures()
    local returned = self:createRecording("returned", { commitResult = false, commitErr = "returned boom" })
    local raised = self:createRecording("raised", { commitResult = "raise", commitErr = "raised boom" })

    local ok, err = returned.commit()
    lu.assertFalse(ok)
    lu.assertEquals(err, "returned boom")

    ok, err = raised.commit()
    lu.assertFalse(ok)
    lu.assertEquals(err, "raised boom")
end

function TestReceipt:testRollbackBeforeCommitIsNoopWithoutDiscard()
    local receipt = self:createRecording("a")

    lu.assertTrue(receipt.rollback())
    lu.assertTrue(receipt.retire())

    lu.assertEquals(self.calls, {})
end

function TestReceipt:testRollbackBeforeCommitRunsDiscardOnce()
    local receipt = self:createRecording("a", { discard = true })

    lu.assertTrue(receipt.rollback())
    lu.assertTrue(receipt.rollback())
    lu.assertTrue(receipt.retire())

    lu.assertEquals(self.calls, { "a:discard" })
end

function TestReceipt:testRollbackAfterFailedCommitRunsDiscardNotRollback()
    local receipt = self:createRecording("a", { commitResult = false, commitErr = "boom", discard = true })

    lu.assertFalse(receipt.commit())
    lu.assertTrue(receipt.rollback())

    lu.assertEquals(self.calls, { "a:commit", "a:discard" })
end

function TestReceipt:testRollbackAfterCommitRunsRollbackOnce()
    local receipt = self:createRecording("a", { discard = true })

    receipt.commit()
    lu.assertTrue(receipt.rollback())
    lu.assertTrue(receipt.rollback())
    lu.assertTrue(receipt.retire())

    lu.assertEquals(self.calls, { "a:commit", "a:rollback" })
end

function TestReceipt:testRetireAfterCommitRunsRetireOnce()
    local receipt = self:createRecording("a")

    receipt.commit()
    lu.assertTrue(receipt.retire())
    lu.assertTrue(receipt.retire())
    lu.assertTrue(receipt.rollback())

    lu.assertEquals(self.calls, { "a:commit", "a:retire" })
end

function TestReceipt:testReleaseFailureIsReportedAndStillReleases()
    local receipt = self:createRecording("a", { rollbackResult = "raise", rollbackErr = "rollback boom" })

    receipt.commit()
    local ok, err = receipt.rollback()

    lu.assertFalse(ok)
    lu.assertEquals(err, "rollback boom")
    lu.assertTrue(receipt.rollback())
    lu.assertEquals(self.calls, { "a:commit", "a:rollback" })
end

function TestReceipt:testCommitAfterReleaseFails()
    local receipt = self:createRecording("a")

    receipt.rollback()
    local ok, err = receipt.commit()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "already released")
    lu.assertEquals(self.calls, {})
end

function TestReceipt:testNoopSucceedsThroughLifecycle()
    local receipt = self.receipt.noop("noop", self.receipt.PHASE_GAME_DATA)

    lu.assertEquals(receipt.name, "noop")
    lu.assertEquals(receipt.phase, self.receipt.PHASE_GAME_DATA)
    lu.assertTrue(receipt.commit())
    lu.assertTrue(receipt.retire())
    lu.assertTrue(receipt.rollback())
end

function TestReceipt:testCompositeCommitsInOrderAndRollsBackInReverse()
    local composite = self.receipt.composite("both", self.receipt.PHASE_EFFECTS, {
        self:createRecording("a"),
        self:createRecording("b"),
    })

    lu.assertTrue(composite.commit())
    lu.assertTrue(composite.rollback())

    lu.assertEquals(self.calls, { "a:commit", "b:commit", "b:rollback", "a:rollback" })
end

function TestReceipt:testCompositeRetiresInReverse()
    local composite = self.receipt.composite("both", self.receipt.PHASE_EFFECTS, {
        self:createRecording("a"),
        self:createRecording("b"),
    })

    composite.commit()
    lu.assertTrue(composite.retire())

    lu.assertEquals(self.calls, { "a:commit", "b:commit", "b:retire", "a:retire" })
end

function TestReceipt:testCompositeFailedCommitRollbackReleasesCommittedChildren()
    local composite = self.receipt.composite("both", self.receipt.PHASE_EFFECTS, {
        self:createRecording("a"),
        self:createRecording("b", { commitResult = false, commitErr = "b boom", discard = true }),
        self:createRecording("c", { discard = true }),
    })

    local ok, err = composite.commit()
    lu.assertFalse(ok)
    lu.assertEquals(err, "b: b boom")

    lu.assertTrue(composite.rollback())
    lu.assertEquals(self.calls, { "a:commit", "b:commit", "c:discard", "b:discard", "a:rollback" })
end

function TestReceipt:testCompositeAggregatesFirstReleaseErrorAndReleasesEveryChild()
    local composite = self.receipt.composite("both", self.receipt.PHASE_EFFECTS, {
        self:createRecording("a", { retireResult = false, retireErr = "a boom" }),
        self:createRecording("b", { retireResult = false, retireErr = "b boom" }),
    })

    composite.commit()
    local ok, err = composite.retire()

    lu.assertFalse(ok)
    lu.assertEquals(err, "b: b boom")
    lu.assertEquals(self.calls, { "a:commit", "b:commit", "b:retire", "a:retire" })
end
