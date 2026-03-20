local lu = require('luaunit')

-- Helper: encode a field to bits and return them as a list
local function encodeToBits(field, value)
    local bits = {}
    lib.encodeField(field, value, function(val, numBits)
        for b = 0, numBits - 1 do
            table.insert(bits, math.floor(val / (2 ^ b)) % 2)
        end
    end)
    return bits
end

-- Helper: decode a field from a list of bits
local function decodeFromBits(field, bits)
    local pos = 1
    return lib.decodeField(field, function(numBits)
        local val = 0
        for b = 0, numBits - 1 do
            if bits[pos] and bits[pos] == 1 then
                val = val + (2 ^ b)
            end
            pos = pos + 1
        end
        return val
    end)
end

-- Helper: round-trip a value through encode -> decode
local function roundTrip(field, value)
    local bits = encodeToBits(field, value)
    return decodeFromBits(field, bits)
end

-- =============================================================================
-- CHECKBOX
-- =============================================================================

TestCheckbox = {}

function TestCheckbox:testEncodeTrue()
    local field = { type = "checkbox", configKey = "X" }
    local bits = encodeToBits(field, true)
    lu.assertEquals(#bits, 1)
    lu.assertEquals(bits[1], 1)
end

function TestCheckbox:testEncodeFalse()
    local field = { type = "checkbox", configKey = "X" }
    local bits = encodeToBits(field, false)
    lu.assertEquals(#bits, 1)
    lu.assertEquals(bits[1], 0)
end

function TestCheckbox:testRoundTripTrue()
    local field = { type = "checkbox", configKey = "X" }
    lu.assertEquals(roundTrip(field, true), true)
end

function TestCheckbox:testRoundTripFalse()
    local field = { type = "checkbox", configKey = "X" }
    lu.assertEquals(roundTrip(field, false), false)
end

function TestCheckbox:testBits()
    local field = { type = "checkbox", configKey = "X" }
    lu.assertEquals(lib.FieldTypes.checkbox.bits(field), 1)
end

function TestCheckbox:testBitsOverride()
    local field = { type = "checkbox", configKey = "X", bits = 3 }
    lu.assertEquals(lib.FieldTypes.checkbox.bits(field), 3)
end

function TestCheckbox:testToStagingTrue()
    lu.assertEquals(lib.FieldTypes.checkbox.toStaging(true), true)
end

function TestCheckbox:testToStagingFalse()
    lu.assertEquals(lib.FieldTypes.checkbox.toStaging(false), false)
end

function TestCheckbox:testToStagingNil()
    lu.assertEquals(lib.FieldTypes.checkbox.toStaging(nil), false)
end

-- =============================================================================
-- DROPDOWN
-- =============================================================================

TestDropdown = {}

local dropdownField = {
    type = "dropdown",
    configKey = "Mode",
    values = { "Vanilla", "Always", "Never" },
    default = "Vanilla",
}

function TestDropdown:testRoundTripFirstValue()
    lu.assertEquals(roundTrip(dropdownField, "Vanilla"), "Vanilla")
end

function TestDropdown:testRoundTripMiddleValue()
    lu.assertEquals(roundTrip(dropdownField, "Always"), "Always")
end

function TestDropdown:testRoundTripLastValue()
    lu.assertEquals(roundTrip(dropdownField, "Never"), "Never")
end

function TestDropdown:testRoundTripDefault()
    lu.assertEquals(roundTrip(dropdownField, nil), "Vanilla")
end

function TestDropdown:testBitsAutoCalculated()
    lu.assertEquals(lib.FieldTypes.dropdown.bits(dropdownField), 2) -- ceil(log2(3)) = 2
end

function TestDropdown:testBitsForTwoValues()
    local field = { type = "dropdown", values = { "A", "B" } }
    lu.assertEquals(lib.FieldTypes.dropdown.bits(field), 1)
end

function TestDropdown:testBitsForFourValues()
    local field = { type = "dropdown", values = { "A", "B", "C", "D" } }
    lu.assertEquals(lib.FieldTypes.dropdown.bits(field), 2)
end

function TestDropdown:testBitsForFiveValues()
    local field = { type = "dropdown", values = { "A", "B", "C", "D", "E" } }
    lu.assertEquals(lib.FieldTypes.dropdown.bits(field), 3) -- ceil(log2(5)) = 3
end

function TestDropdown:testBitsOverride()
    local field = { type = "dropdown", values = { "A", "B" }, bits = 4 }
    lu.assertEquals(lib.FieldTypes.dropdown.bits(field), 4)
end

-- =============================================================================
-- RADIO
-- =============================================================================

TestRadio = {}

local radioField = {
    type = "radio",
    configKey = "Speed",
    values = { "Slow", "Normal", "Fast" },
    default = "Normal",
}

function TestRadio:testRoundTripAllValues()
    for _, v in ipairs(radioField.values) do
        lu.assertEquals(roundTrip(radioField, v), v)
    end
end

function TestRadio:testRoundTripDefault()
    lu.assertEquals(roundTrip(radioField, nil), "Normal")
end

function TestRadio:testBitsAutoCalculated()
    lu.assertEquals(lib.FieldTypes.radio.bits(radioField), 2)
end

-- =============================================================================
-- MULTI-FIELD ROUND-TRIP
-- =============================================================================

TestMultiField = {}

function TestMultiField:testSequentialEncodeDecodeRoundTrips()
    -- Simulate encoding multiple fields sequentially (like the hash does)
    local schema = {
        { type = "checkbox", configKey = "A" },
        { type = "dropdown", configKey = "B", values = { "X", "Y", "Z" }, default = "X" },
        { type = "checkbox", configKey = "C" },
        { type = "radio",    configKey = "D", values = { "Low", "Mid", "High" }, default = "Low" },
    }
    local values = { true, "Y", false, "High" }

    -- Encode all fields
    local allBits = {}
    for i, field in ipairs(schema) do
        lib.encodeField(field, values[i], function(val, numBits)
            for b = 0, numBits - 1 do
                table.insert(allBits, math.floor(val / (2 ^ b)) % 2)
            end
        end)
    end

    -- Decode all fields
    local pos = 1
    local readBits = function(numBits)
        local val = 0
        for b = 0, numBits - 1 do
            if allBits[pos] and allBits[pos] == 1 then
                val = val + (2 ^ b)
            end
            pos = pos + 1
        end
        return val
    end

    local decoded = {}
    for _, field in ipairs(schema) do
        table.insert(decoded, lib.decodeField(field, readBits))
    end

    lu.assertEquals(decoded[1], true)
    lu.assertEquals(decoded[2], "Y")
    lu.assertEquals(decoded[3], false)
    lu.assertEquals(decoded[4], "High")
end
