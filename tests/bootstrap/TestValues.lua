local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestValues = {}

function TestValues:setUp()
    self.harness = createLibHarness()
    self.values = self.harness.values
end

function TestValues:testDeepCopyPreservesCyclesWithoutSharingTables()
    local key = { name = "key" }
    local source = {
        nested = {
            value = 7,
        },
        [key] = "keyed",
    }
    source.self = source

    local copy = self.values.deepCopy(source)

    lu.assertNotIs(copy, source)
    lu.assertNotIs(copy.nested, source.nested)
    lu.assertEquals(copy.nested.value, 7)
    lu.assertIs(copy.self, copy)

    local copiedKey
    for candidate in pairs(copy) do
        if type(candidate) == "table" and candidate.name == "key" then
            copiedKey = candidate
        end
    end
    lu.assertNotNil(copiedKey)
    lu.assertNotIs(copiedKey, key)
    lu.assertEquals(copy[copiedKey], "keyed")
end

function TestValues:testDeepEqualHandlesCyclesAndDetectsMismatches()
    local a = {
        label = "same",
        nested = {
            value = 1,
        },
    }
    local b = {
        label = "same",
        nested = {
            value = 1,
        },
    }
    a.self = a
    b.self = b

    lu.assertTrue(self.values.deepEqual(a, b))

    b.nested.value = 2

    lu.assertFalse(self.values.deepEqual(a, b))
end
