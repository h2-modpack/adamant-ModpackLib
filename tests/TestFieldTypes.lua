local lu = require('luaunit')

local function makeStore(definition, config)
    config = config or {}
    return lib.createStore(config, definition), config
end

local function makeBasicImgui()
    local state = {
        buttonResponses = {},
        checkboxResponses = {},
        selectables = {},
        pushIds = {},
        cursorPosX = 0,
        setCursorPosXCalls = {},
        pushItemWidths = {},
        sameLineCalls = 0,
    }

    local imgui = {
        _state = state,
        Checkbox = function(_, _, current)
            local nextResponse = table.remove(state.checkboxResponses, 1)
            if nextResponse ~= nil then
                return nextResponse, nextResponse ~= current
            end
            return current, false
        end,
        BeginCombo = function()
            return false
        end,
        EndCombo = function() end,
        Selectable = function()
            local nextResponse = table.remove(state.selectables, 1)
            return nextResponse == true
        end,
        RadioButton = function()
            local nextResponse = table.remove(state.selectables, 1)
            return nextResponse == true
        end,
        Text = function() end,
        TextColored = function() end,
        CalcTextSize = function(text)
            return #(tostring(text or "")) * 8
        end,
        SameLine = function()
            state.sameLineCalls = state.sameLineCalls + 1
        end,
        NewLine = function() end,
        IsItemHovered = function() return false end,
        SetTooltip = function() end,
        PushItemWidth = function(a, b)
            table.insert(state.pushItemWidths, b or a)
        end,
        PopItemWidth = function() end,
        PushID = function(_, value)
            table.insert(state.pushIds, value)
        end,
        PopID = function() end,
        Indent = function() end,
        Unindent = function() end,
        Separator = function() end,
        CollapsingHeader = function()
            return true
        end,
        GetCursorPosX = function()
            return state.cursorPosX
        end,
        GetStyle = function()
            return {
                FramePadding = { x = 4, y = 3 },
                ItemSpacing = { x = 8, y = 4 },
            }
        end,
        SetCursorPosX = function(x)
            state.cursorPosX = x
            table.insert(state.setCursorPosXCalls, x)
        end,
        Button = function()
            local nextResponse = table.remove(state.buttonResponses, 1)
            return nextResponse == true
        end,
    }

    return imgui
end

TestStorageTypes = {}

function TestStorageTypes:testBoolStorageRoundTripsHash()
    local node = { type = "bool", alias = "Enabled", configKey = "Enabled", default = false }
    lib.validateStorage({ node }, "Test")

    lu.assertEquals(lib.StorageTypes.bool.toHash(node, true), "1")
    lu.assertEquals(lib.StorageTypes.bool.toHash(node, false), "0")
    lu.assertTrue(lib.StorageTypes.bool.fromHash(node, "1"))
    lu.assertFalse(lib.StorageTypes.bool.fromHash(node, "0"))
end

function TestStorageTypes:testPackedIntDerivesChildAliasesAndDefault()
    local storage = {
        {
            type = "packedInt",
            alias = "Packed",
            configKey = "Packed",
            bits = {
                { alias = "Flag", offset = 0, width = 1, type = "bool", default = true },
                { alias = "Mode", offset = 1, width = 2, type = "int", default = 2 },
            },
        },
    }

    lib.validateStorage(storage, "PackedTest")

    local aliases = lib.getStorageAliases(storage)
    lu.assertNotNil(aliases.Packed)
    lu.assertNotNil(aliases.Flag)
    lu.assertNotNil(aliases.Mode)
    lu.assertEquals(aliases.Packed.default, 5)
    lu.assertTrue(aliases.Flag.default)
    lu.assertEquals(aliases.Mode.default, 2)
    lu.assertEquals(aliases.Flag.parent.alias, "Packed")
end

TestUiNodes = {}

function TestUiNodes:testDrawCheckboxNodeWritesAliasBackIntoUiState()
    local definition = {
        storage = {
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
        },
    }
    local store = makeStore(definition, { Enabled = true })
    local imgui = makeBasicImgui()
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertFalse(store.uiState.get("Enabled"))
end

function TestUiNodes:testDrawUiNodeRespectsVisibleIfAlias()
    local definition = {
        storage = {
            { type = "bool", alias = "Gate", configKey = "Gate", default = false },
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = "Gate" },
        },
    }
    local store = makeStore(definition, { Gate = false, Enabled = true })
    local imgui = makeBasicImgui()
    local checkboxCalls = 0
    imgui.Checkbox = function(_, _, current)
        checkboxCalls = checkboxCalls + 1
        return current, false
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(checkboxCalls, 0)
end

function TestUiNodes:testDrawUiNodeRespectsVisibleIfValue()
    local definition = {
        storage = {
            { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = { alias = "Mode", value = "Forced" } },
        },
    }
    local store = makeStore(definition, { Mode = "Forced", Enabled = true })
    local imgui = makeBasicImgui()
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertFalse(store.uiState.get("Enabled"))
end

function TestUiNodes:testDrawUiNodeRespectsVisibleIfAnyOf()
    local definition = {
        storage = {
            { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = { alias = "Mode", anyOf = { "Forced", "Charybdis" } } },
        },
    }
    local store = makeStore(definition, { Mode = "Charybdis", Enabled = true })
    local imgui = makeBasicImgui()
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertFalse(store.uiState.get("Enabled"))
end

function TestUiNodes:testDrawSteppedRangeNodeWritesBothAliases()
    local definition = {
        storage = {
            { type = "int", alias = "MinDepth", configKey = "MinDepth", default = 2, min = 1, max = 10 },
            { type = "int", alias = "MaxDepth", configKey = "MaxDepth", default = 8, min = 1, max = 10 },
        },
        ui = {
            { type = "steppedRange", binds = { min = "MinDepth", max = "MaxDepth" }, label = "Depth", min = 1, max = 10, step = 1 },
        },
    }
    local store = makeStore(definition, { MinDepth = 2, MaxDepth = 8 })
    local imgui = makeBasicImgui()
    imgui._state.buttonResponses = {
        false, true,   -- min: "-" then "+"
        true, false,   -- max: "-" then "+"
    }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertEquals(store.uiState.get("MinDepth"), 3)
    lu.assertEquals(store.uiState.get("MaxDepth"), 7)
end

function TestUiNodes:testCollectQuickUiNodesRecursesThroughLayoutChildren()
    local nodes = {
        {
            type = "group",
            label = "Outer",
            children = {
                { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", quick = true },
                {
                    type = "group",
                    label = "Inner",
                    children = {
                        { type = "stepper", binds = { value = "Count" }, label = "Count", quick = true, min = 1, max = 9, step = 1 },
                    },
                },
            },
        },
    }

    local quick = lib.collectQuickUiNodes(nodes)

    lu.assertEquals(#quick, 2)
    lu.assertEquals(quick[1].binds and quick[1].binds.value, "Enabled")
    lu.assertEquals(quick[2].binds and quick[2].binds.value, "Count")
end

function TestUiNodes:testCollectQuickUiNodesSupportsCustomTypes()
    local nodes = {
        {
            type = "fancyGroup",
            children = {
                { type = "fancyToggle", binds = { value = "Enabled" }, label = "Enabled", quick = true },
            },
        },
    }
    local customTypes = {
        widgets = {
            fancyToggle = {
                binds = { value = { storageType = "bool" } },
                validate = function() end,
                draw = function() end,
            },
        },
        layouts = {
            fancyGroup = {
                validate = function() end,
                render = function() return true end,
            },
        },
    }

    local quick = lib.collectQuickUiNodes(nodes, nil, customTypes)

    lu.assertEquals(#quick, 1)
    lu.assertEquals(quick[1].type, "fancyToggle")
end

function TestUiNodes:testGetQuickUiNodeIdFallsBackToBinds()
    local node = {
        type = "checkbox",
        binds = { value = "Enabled" },
        label = "Enabled",
        quick = true,
    }

    lu.assertEquals(lib.getQuickUiNodeId(node), "value=Enabled")
end

function TestUiNodes:testGetQuickUiNodeIdPrefersExplicitQuickId()
    local node = {
        type = "checkbox",
        binds = { value = "Enabled" },
        label = "Enabled",
        quick = true,
        quickId = "CurrentAspect",
    }

    lu.assertEquals(lib.getQuickUiNodeId(node), "CurrentAspect")
end

function TestUiNodes:testDrawUiNodeReturnsChangedWhenLayoutChildChanges()
    local definition = {
        storage = {
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            {
                type = "group",
                label = "Outer",
                children = {
                    { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
                },
            },
        },
    }
    local store = makeStore(definition, { Enabled = true })
    local imgui = makeBasicImgui()
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertFalse(store.uiState.get("Enabled"))
end

function TestUiNodes:testDropdownGeometryControlsStartAndWidth()
    local definition = {
        storage = {
            { type = "string", alias = "Mode", configKey = "Mode", default = "A" },
        },
        ui = {
            {
                type = "dropdown",
                binds = { value = "Mode" },
                label = "Mode",
                values = { "A", "B" },
                geometry = { controlStart = 220, controlWidth = 180 },
            },
        },
    }
    local store = makeStore(definition, { Mode = "A" })
    local imgui = makeBasicImgui()
    imgui._state.cursorPosX = 12

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState, 300)

    lu.assertFalse(changed)
    lu.assertEquals(imgui._state.sameLineCalls, 1)
    lu.assertEquals(imgui._state.setCursorPosXCalls[1], 232)
    lu.assertEquals(imgui._state.pushItemWidths[1], 180)
end

function TestUiNodes:testSteppedRangeGeometryAppliesWithoutLabel()
    local definition = {
        storage = {
            { type = "int", alias = "MinDepth", configKey = "MinDepth", default = 2, min = 1, max = 10 },
            { type = "int", alias = "MaxDepth", configKey = "MaxDepth", default = 8, min = 1, max = 10 },
        },
        ui = {
            {
                type = "steppedRange",
                binds = { min = "MinDepth", max = "MaxDepth" },
                label = "",
                min = 1,
                max = 10,
                geometry = {
                    separatorStart = 180,
                    control2Start = 220,
                    decrementStart = 0,
                    valueWidth = 24,
                    valueAlign = "center",
                    incrementStart = 42,
                },
            },
        },
    }
    local store = makeStore(definition, { MinDepth = 2, MaxDepth = 8 })
    local imgui = makeBasicImgui()
    imgui._state.cursorPosX = 16

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertTrue(#imgui._state.setCursorPosXCalls >= 5)
    local sawCenteredFirstValue = false
    local sawFirstValueStart = false
    local sawFirstIncrementStart = false
    local sawSeparatorStart = false
    for _, x in ipairs(imgui._state.setCursorPosXCalls) do
        if x == 40 then
            sawFirstValueStart = true
        end
        if x == 48 then
            sawCenteredFirstValue = true
        end
        if x == 58 then
            sawFirstIncrementStart = true
        end
        if x == 196 then
            sawSeparatorStart = true
        end
    end
    lu.assertTrue(sawFirstValueStart)
    lu.assertTrue(sawCenteredFirstValue)
    lu.assertTrue(sawFirstIncrementStart)
    lu.assertTrue(sawSeparatorStart)
    local sawSecondControlStart = false
    local sawSecondValueStart = false
    local sawCenteredSecondValue = false
    local sawSecondIncrementStart = false
    for _, x in ipairs(imgui._state.setCursorPosXCalls) do
        if x == 236 then
            sawSecondControlStart = true
        end
        if x == 260 then
            sawSecondValueStart = true
        end
        if x == 268 then
            sawCenteredSecondValue = true
        end
        if x == 278 then
            sawSecondIncrementStart = true
        end
    end
    lu.assertTrue(sawSecondControlStart)
    lu.assertTrue(sawSecondValueStart)
    lu.assertTrue(sawCenteredSecondValue)
    lu.assertTrue(sawSecondIncrementStart)
end

function TestUiNodes:testStepperCentersValueWithinExplicitValueWidth()
    local definition = {
        storage = {
            { type = "int", alias = "Count", configKey = "Count", default = 7, min = 1, max = 10 },
        },
        ui = {
            {
                type = "stepper",
                binds = { value = "Count" },
                label = "",
                min = 1,
                max = 10,
                geometry = {
                    decrementStart = 0,
                    valueWidth = 28,
                    incrementStart = 60,
                    valueAlign = "center",
                },
            },
        },
    }
    local store = makeStore(definition, { Count = 7 })
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    local sawCenteredValue = false
    local sawIncrementStart = false
    for _, x in ipairs(imgui._state.setCursorPosXCalls) do
        if x == 24 then
            sawCenteredValue = true
        end
        if x == 60 then
            sawIncrementStart = true
        end
    end
    lu.assertTrue(sawCenteredValue)
    lu.assertTrue(sawIncrementStart)
end
