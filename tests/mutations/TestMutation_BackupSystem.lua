local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestMutation_BackupSystem = {}

function TestMutation_BackupSystem:setUp()
    self.harness = createLibHarness()
    self.mutation = self.harness.mutation
    self.mutationPlan = self.harness.mutationPlan
end

function TestMutation_BackupSystem:testBackupAndRestoreScalar()
    local backup, restore = self.mutationPlan.createBackup()
    local tbl = { HP = 100, Name = "Player" }

    backup(tbl, "HP")
    tbl.HP = 999

    lu.assertEquals(tbl.HP, 999)
    restore()
    lu.assertEquals(tbl.HP, 100)
end

function TestMutation_BackupSystem:testBackupAndRestoreMultipleKeys()
    local backup, restore = self.mutationPlan.createBackup()
    local tbl = { A = 1, B = 2, C = 3 }

    backup(tbl, "A", "B")
    tbl.A = 10
    tbl.B = 20

    restore()
    lu.assertEquals(tbl.A, 1)
    lu.assertEquals(tbl.B, 2)
    lu.assertEquals(tbl.C, 3)
end

function TestMutation_BackupSystem:testBackupNilValue()
    local backup, restore = self.mutationPlan.createBackup()
    local tbl = { A = 1 }

    backup(tbl, "Missing")
    tbl.Missing = "added"

    restore()
    lu.assertIsNil(tbl.Missing)
end

function TestMutation_BackupSystem:testBackupTable()
    local backup, restore = self.mutationPlan.createBackup()
    local inner = { x = 1, y = 2 }
    local tbl = { Data = inner }

    backup(tbl, "Data")
    tbl.Data.x = 99
    tbl.Data.y = 99

    restore()
    lu.assertEquals(tbl.Data.x, 1)
    lu.assertEquals(tbl.Data.y, 2)
end

function TestMutation_BackupSystem:testBackupOnlyFirstCall()
    local backup, restore = self.mutationPlan.createBackup()
    local tbl = { X = "original" }

    backup(tbl, "X")
    tbl.X = "changed"
    backup(tbl, "X")

    restore()
    lu.assertEquals(tbl.X, "original")
end

function TestMutation_BackupSystem:testMultipleTables()
    local backup, restore = self.mutationPlan.createBackup()
    local t1 = { A = 1 }
    local t2 = { B = 2 }

    backup(t1, "A")
    backup(t2, "B")
    t1.A = 10
    t2.B = 20

    restore()
    lu.assertEquals(t1.A, 1)
    lu.assertEquals(t2.B, 2)
end

function TestMutation_BackupSystem:testIsolatedSystems()
    local backup1, restore1 = self.mutationPlan.createBackup()
    local _, restore2 = self.mutationPlan.createBackup()
    local tbl = { X = "original" }

    backup1(tbl, "X")
    tbl.X = "changed"

    restore2()
    lu.assertEquals(tbl.X, "changed")

    restore1()
    lu.assertEquals(tbl.X, "original")
end
