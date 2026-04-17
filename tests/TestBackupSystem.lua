local lu = require('luaunit')

TestBackupSystem = {}

function TestBackupSystem:testBackupAndRestoreScalar()
    local backup, restore = lib.mutation.createBackup()
    local tbl = { HP = 100, Name = "Player" }

    backup(tbl, "HP")
    tbl.HP = 999

    lu.assertEquals(tbl.HP, 999)
    restore()
    lu.assertEquals(tbl.HP, 100)
end

function TestBackupSystem:testBackupAndRestoreMultipleKeys()
    local backup, restore = lib.mutation.createBackup()
    local tbl = { A = 1, B = 2, C = 3 }

    backup(tbl, "A", "B")
    tbl.A = 10
    tbl.B = 20

    restore()
    lu.assertEquals(tbl.A, 1)
    lu.assertEquals(tbl.B, 2)
    lu.assertEquals(tbl.C, 3) -- untouched
end

function TestBackupSystem:testBackupNilValue()
    local backup, restore = lib.mutation.createBackup()
    local tbl = { A = 1 }

    backup(tbl, "Missing")
    tbl.Missing = "added"

    restore()
    lu.assertIsNil(tbl.Missing)
end

function TestBackupSystem:testBackupTable()
    local backup, restore = lib.mutation.createBackup()
    local inner = { x = 1, y = 2 }
    local tbl = { Data = inner }

    backup(tbl, "Data")
    tbl.Data.x = 99
    tbl.Data.y = 99

    restore()
    lu.assertEquals(tbl.Data.x, 1)
    lu.assertEquals(tbl.Data.y, 2)
end

function TestBackupSystem:testBackupOnlyFirstCall()
    local backup, restore = lib.mutation.createBackup()
    local tbl = { X = "original" }

    backup(tbl, "X")
    tbl.X = "changed"
    backup(tbl, "X") -- should not overwrite saved value

    restore()
    lu.assertEquals(tbl.X, "original")
end

function TestBackupSystem:testMultipleTables()
    local backup, restore = lib.mutation.createBackup()
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

function TestBackupSystem:testIsolatedSystems()
    local backup1, restore1 = lib.mutation.createBackup()
    local backup2, restore2 = lib.mutation.createBackup()
    local tbl = { X = "original" }

    backup1(tbl, "X")
    tbl.X = "changed"

    restore2() -- should not affect backup1's state
    lu.assertEquals(tbl.X, "changed")

    restore1()
    lu.assertEquals(tbl.X, "original")
end
