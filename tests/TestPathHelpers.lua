local lu = require('luaunit')

TestReadPath = {}

function TestReadPath:testStringKey()
    local tbl = { Mode = "Fast", Count = 3 }
    local val, parent, leaf = lib.readPath(tbl, "Mode")
    lu.assertEquals(val, "Fast")
    lu.assertEquals(parent, tbl)
    lu.assertEquals(leaf, "Mode")
end

function TestReadPath:testNestedPath()
    local tbl = { First = { Second = "deep" } }
    local val, parent, leaf = lib.readPath(tbl, {"First", "Second"})
    lu.assertEquals(val, "deep")
    lu.assertEquals(parent, tbl.First)
    lu.assertEquals(leaf, "Second")
end

function TestReadPath:testMissingIntermediateReturnsNil()
    local tbl = { A = 1 }
    local val, parent, leaf = lib.readPath(tbl, {"Missing", "Key"})
    lu.assertIsNil(val)
    lu.assertIsNil(parent)
    lu.assertIsNil(leaf)
end

function TestReadPath:testSingleElementPath()
    local tbl = { X = 42 }
    local val = lib.readPath(tbl, {"X"})
    lu.assertEquals(val, 42)
end

TestWritePath = {}

function TestWritePath:testStringKey()
    local tbl = {}
    lib.writePath(tbl, "Key", "Value")
    lu.assertEquals(tbl.Key, "Value")
end

function TestWritePath:testNestedPathCreatesIntermediates()
    local tbl = {}
    lib.writePath(tbl, {"A", "B", "C"}, 99)
    lu.assertEquals(tbl.A.B.C, 99)
end

function TestWritePath:testOverwritesExistingValue()
    local tbl = { X = "old" }
    lib.writePath(tbl, "X", "new")
    lu.assertEquals(tbl.X, "new")
end

function TestWritePath:testPreservesExistingIntermediates()
    local tbl = { A = { existing = true } }
    lib.writePath(tbl, {"A", "B"}, "added")
    lu.assertEquals(tbl.A.B, "added")
    lu.assertEquals(tbl.A.existing, true)
end
