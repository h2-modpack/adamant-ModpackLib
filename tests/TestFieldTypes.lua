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
        newLineCalls = 0,
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
        NewLine = function()
            state.newLineCalls = state.newLineCalls + 1
        end,
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

function TestUiNodes:testCheckboxCanUseControlSlotGeometry()
    local definition = {
        storage = {
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            {
                type = "checkbox",
                binds = { value = "Enabled" },
                label = "Enabled",
                geometry = {
                    slots = {
                        { name = "control", start = 120 },
                    },
                },
            },
        },
    }
    local store = makeStore(definition, { Enabled = true })
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(imgui._state.setCursorPosXCalls[1], 120)
end

function TestUiNodes:testTextWidgetCanUseValueSlotGeometryAndColor()
    local imgui = makeBasicImgui()
    local coloredCalls = {}
    imgui.TextColored = function(r, g, b, a, text)
        table.insert(coloredCalls, { r = r, g = g, b = b, a = a, text = text })
    end
    local node = {
        type = "text",
        text = "Epic",
        color = { 1, 0.5, 0.25, 1 },
        geometry = {
            slots = {
                { name = "value", start = 20, width = 100, align = "center" },
            },
        },
    }

    lib.prepareWidgetNode(node, "TextWidget")
    local changed = lib.drawUiNode(imgui, node, { view = {} })

    lu.assertFalse(changed)
    lu.assertEquals(#coloredCalls, 1)
    lu.assertEquals(coloredCalls[1].text, "Epic")
    lu.assertEquals(imgui._state.setCursorPosXCalls[1], 20)
    lu.assertEquals(imgui._state.setCursorPosXCalls[2], 54)
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
    lu.assertEquals(imgui._state.newLineCalls, 0)
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

function TestUiNodes:testCustomWidgetCanRenderThroughDraw()
    local definition = {
        storage = {
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        customTypes = {
            widgets = {
                fancyToggle = {
                    binds = { value = { storageType = "bool" } },
                    validate = function() end,
                    draw = function(imgui, _, bound)
                        local current = bound.value:get()
                        local nextValue, changed = imgui.Checkbox("Fancy", current == true)
                        if changed then
                            bound.value:set(nextValue)
                            return true
                        end
                        return false
                    end,
                },
            },
        },
        ui = {
            { type = "fancyToggle", binds = { value = "Enabled" } },
        },
    }
    local store = makeStore(definition, { Enabled = true })
    local imgui = makeBasicImgui()
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState, nil, definition.customTypes)

    lu.assertTrue(changed)
    lu.assertFalse(store.uiState.get("Enabled"))
end

function TestUiNodes:testCustomWidgetCanUsePublicDrawWidgetSlotsHelper()
    local definition = {
        storage = {
            { type = "int", alias = "Count", configKey = "Count", default = 2, min = 0, max = 9 },
        },
        customTypes = {
            widgets = {
                fancyStepper = {
                    binds = { value = { storageType = "int" } },
                    slots = { "decrement", "value", "increment" },
                    validate = function() end,
                    draw = function(imgui, node, bound)
                        local current = bound.value:get() or 0
                        local nextValue = current
                        local changed = lib.drawWidgetSlots(imgui, node, {
                            {
                                name = "decrement",
                                draw = function()
                                    if imgui.Button("-") and current > 0 then
                                        nextValue = current - 1
                                    end
                                    return false
                                end,
                            },
                            {
                                name = "value",
                                sameLine = true,
                                draw = function()
                                    imgui.Text(tostring(current))
                                    return false
                                end,
                            },
                            {
                                name = "increment",
                                sameLine = true,
                                draw = function()
                                    if imgui.Button("+") and current < 9 then
                                        nextValue = current + 1
                                    end
                                    return false
                                end,
                            },
                        })
                        if nextValue ~= current then
                            bound.value:set(nextValue)
                            return true
                        end
                        return changed
                    end,
                },
            },
        },
        ui = {
            {
                type = "fancyStepper",
                binds = { value = "Count" },
                geometry = {
                    slots = {
                        { name = "decrement", start = 0 },
                        { name = "value", start = 40, width = 40, align = "center" },
                        { name = "increment", start = 100 },
                    },
                },
            },
        },
    }
    local store = makeStore(definition, { Count = 2 })
    local imgui = makeBasicImgui()
    imgui._state.buttonResponses = { false, true }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState, nil, definition.customTypes)

    lu.assertTrue(changed)
    lu.assertEquals(store.uiState.get("Count"), 3)
end

function TestUiNodes:testDrawWidgetSlotsHelperCanUseLooseGeometryFromDirectNodeStub()
    local imgui = makeBasicImgui()
    local node = {
        geometry = {
            slots = {
                { name = "left", start = 0 },
                { name = "right", start = 80 },
            },
        },
    }

    local changed = lib.drawWidgetSlots(imgui, node, {
        {
            name = "left",
            draw = function()
                imgui.Text("L")
                return false
            end,
        },
        {
            name = "right",
            draw = function()
                imgui.Text("R")
                return false
            end,
        },
    })

    lu.assertFalse(changed)
    lu.assertNil(node._slotGeometry)

    local saw0 = false
    local saw80 = false
    for _, x in ipairs(imgui._state.setCursorPosXCalls) do
        if x == 0 then
            saw0 = true
        elseif x == 80 then
            saw80 = true
        end
    end
    lu.assertTrue(saw0)
    lu.assertTrue(saw80)
end

function TestUiNodes:testPrepareWidgetNodeCachesSlotGeometryForDirectCustomWidget()
    local customTypes = {
        widgets = {
            rarityBadge = {
                binds = { value = { storageType = "int" } },
                slots = { "decrement", "value", "increment" },
                defaultGeometry = {
                    slots = {
                        { name = "decrement", start = 0 },
                        { name = "value", start = 24, width = 60, align = "center" },
                        { name = "increment", start = 92 },
                    },
                },
                validate = function() end,
                draw = function() end,
            },
        },
    }
    local node = {
        type = "rarityBadge",
    }

    lib.prepareWidgetNode(node, "DirectRarityBadge", customTypes)

    lu.assertTrue(type(node._slotGeometry) == "table")
    lu.assertNotNil(node._defaultSlotGeometry)
    lu.assertEquals(node._defaultSlotGeometry.increment.start, 92)
    lu.assertEquals(node._defaultSlotGeometry.value.width, 60)
    lu.assertEquals(node._defaultSlotGeometry.value.align, "center")
    lu.assertTrue(type(node._imguiId) == "string" and node._imguiId ~= "")
end

function TestUiNodes:testNodeGeometryOverridesWidgetDefaultGeometry()
    local customTypes = {
        widgets = {
            fancyStepper = {
                binds = { value = { storageType = "int" } },
                slots = { "decrement", "value", "increment" },
                defaultGeometry = {
                    slots = {
                        { name = "value", start = 24, width = 60, align = "center" },
                    },
                },
                validate = function() end,
                draw = function() end,
            },
        },
    }
    local node = {
        type = "fancyStepper",
        geometry = {
            slots = {
                { name = "value", width = 80, align = "right" },
            },
        },
    }

    lib.prepareWidgetNode(node, "FancyStepperOverride", customTypes)

    local valueSlot = node._slotGeometry.value
    lu.assertNotNil(valueSlot)
    lu.assertEquals(valueSlot.width, 80)
    lu.assertEquals(valueSlot.align, "right")
    lu.assertEquals(node._defaultSlotGeometry.value.start, 24)
    lu.assertEquals(valueSlot.align, "right")
end

function TestUiNodes:testZeroBindCustomWidgetsGetDistinctFallbackImguiIds()
    local customTypes = {
        widgets = {
            rarityBadge = {
                binds = {},
                slots = { "value" },
                validate = function() end,
                draw = function(imgui, node)
                    imgui.Text(node.text or "")
                    return false
                end,
            },
        },
    }
    local nodeA = { type = "rarityBadge", text = "A" }
    local nodeB = { type = "rarityBadge", text = "B" }

    lib.prepareWidgetNode(nodeA, "RarityBadgeA", customTypes)
    lib.prepareWidgetNode(nodeB, "RarityBadgeB", customTypes)

    lu.assertTrue(type(nodeA._imguiId) == "string" and nodeA._imguiId ~= "")
    lu.assertTrue(type(nodeB._imguiId) == "string" and nodeB._imguiId ~= "")
    lu.assertNotEquals(nodeA._imguiId, nodeB._imguiId)
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

function TestUiNodes:testPanelLayoutCanPlaceChildrenIntoColumnsAndLines()
    local definition = {
        storage = {
            { type = "string", alias = "ModeA", configKey = "ModeA", default = "A" },
            { type = "string", alias = "ModeB", configKey = "ModeB", default = "A" },
            { type = "string", alias = "ModeC", configKey = "ModeC", default = "A" },
        },
        ui = {
            {
                type = "panel",
                columns = {
                    { name = "left", start = 0, width = 100 },
                    { name = "right", start = 120, width = 140 },
                },
                children = {
                    {
                        type = "dropdown",
                        binds = { value = "ModeA" },
                        values = { "A", "B" },
                        panel = { column = "left", line = 1, slots = { "control" } },
                    },
                    {
                        type = "dropdown",
                        binds = { value = "ModeB" },
                        values = { "A", "B" },
                        panel = { column = "right", line = 1, slots = { "control" } },
                    },
                    {
                        type = "dropdown",
                        binds = { value = "ModeC" },
                        values = { "A", "B" },
                        panel = { column = "left", line = 2, slots = { "control" } },
                    },
                },
            },
        },
    }
    local store = makeStore(definition, {
        ModeA = "A",
        ModeB = "A",
        ModeC = "A",
    })
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(imgui._state.newLineCalls, 1)

    local saw0 = false
    local saw120 = false
    for _, x in ipairs(imgui._state.setCursorPosXCalls) do
        if x == 0 then
            saw0 = true
        elseif x == 120 then
            saw120 = true
        end
    end
    lu.assertTrue(saw0)
    lu.assertTrue(saw120)

    lu.assertEquals(#imgui._state.pushItemWidths, 3)
    lu.assertEquals(imgui._state.pushItemWidths[1], 100)
    lu.assertEquals(imgui._state.pushItemWidths[2], 140)
    lu.assertEquals(imgui._state.pushItemWidths[3], 100)
end

function TestUiNodes:testCustomLayoutCanDelegateChildRenderingThroughDrawChild()
    local sawDrawChild = false
    local definition = {
        storage = {
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        customTypes = {
            layouts = {
                delegatingLayout = {
                    handlesChildren = true,
                    validate = function() end,
                    render = function(imgui, node, drawChild)
                        sawDrawChild = type(drawChild) == "function"
                        local changed = false
                        for _, child in ipairs(node.children or {}) do
                            if drawChild(child) then
                                changed = true
                            end
                        end
                        return true, changed
                    end,
                },
            },
        },
        ui = {
            {
                type = "delegatingLayout",
                children = {
                    { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
                },
            },
        },
    }
    local store = makeStore(definition, { Enabled = true })
    local imgui = makeBasicImgui()
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState, nil, definition.customTypes)

    lu.assertTrue(sawDrawChild)
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
                geometry = {
                    slots = {
                        { name = "control", start = 220, width = 180 },
                    },
                },
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
                    slots = {
                        { name = "min.decrement", start = 0 },
                        { name = "min.value", start = 24, width = 24, align = "center" },
                        { name = "min.increment", start = 42 },
                        { name = "separator", start = 180 },
                        { name = "max.decrement", start = 220 },
                        { name = "max.value", start = 244, width = 24, align = "center" },
                        { name = "max.increment", start = 262 },
                    },
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

function TestUiNodes:testSteppedRangeDrawDoesNotMutatePreparedStepperBounds()
    local definition = {
        storage = {
            { type = "int", alias = "MinDepth", configKey = "MinDepth", default = 2, min = 1, max = 10 },
            { type = "int", alias = "MaxDepth", configKey = "MaxDepth", default = 8, min = 1, max = 10 },
        },
        ui = {
            {
                type = "steppedRange",
                binds = { min = "MinDepth", max = "MaxDepth" },
                label = "Depth",
                min = 1,
                max = 10,
            },
        },
    }
    local store = makeStore(definition, { MinDepth = 4, MaxDepth = 6 })
    local node = definition.ui[1]
    local minStepper = node._minStepper
    local maxStepper = node._maxStepper
    local initialMinStepperMax = minStepper.max
    local initialMaxStepperMin = maxStepper.min

    local changed = lib.drawUiNode(makeBasicImgui(), node, store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(minStepper.max, initialMinStepperMax)
    lu.assertEquals(maxStepper.min, initialMaxStepperMin)
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
                    slots = {
                        { name = "decrement", start = 0 },
                        { name = "value", start = 24, width = 28, align = "center" },
                        { name = "increment", start = 60 },
                    },
                },
            },
        },
    }
    local store = makeStore(definition, { Count = 7 })
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    local sawValueStart = false
    local sawCenteredValue = false
    local sawIncrementStart = false
    for _, x in ipairs(imgui._state.setCursorPosXCalls) do
        if x == 24 then
            sawValueStart = true
        end
        if x == 34 then
            sawCenteredValue = true
        end
        if x == 60 then
            sawIncrementStart = true
        end
    end
    lu.assertTrue(sawValueStart)
    lu.assertTrue(sawCenteredValue)
    lu.assertTrue(sawIncrementStart)
end

function TestUiNodes:testStepperGeometrySortsSlotsByLineThenStart()
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
                    slots = {
                        { name = "decrement", line = 1, start = 0 },
                        { name = "value", line = 2, start = 60 },
                        { name = "increment", line = 2, start = 24 },
                    },
                },
            },
        },
    }
    local store = makeStore(definition, { Count = 7 })
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertTrue(imgui._state.newLineCalls >= 1)

    local first24 = nil
    local first60 = nil
    for index, x in ipairs(imgui._state.setCursorPosXCalls) do
        if x == 24 and first24 == nil then
            first24 = index
        elseif x == 60 and first60 == nil then
            first60 = index
        end
    end
    lu.assertNotNil(first24)
    lu.assertNotNil(first60)
    lu.assertTrue(first24 < first60)
end

function TestUiNodes:testRadioGeometryCanLayOutOptionsAcrossLines()
    local definition = {
        storage = {
            { type = "string", alias = "Mode", configKey = "Mode", default = "A" },
        },
        ui = {
            {
                type = "radio",
                binds = { value = "Mode" },
                label = "",
                values = { "A", "B", "C", "D" },
                geometry = {
                    slots = {
                        { name = "option:1", line = 1, start = 0 },
                        { name = "option:2", line = 1, start = 80 },
                        { name = "option:3", line = 2, start = 0 },
                        { name = "option:4", line = 2, start = 80 },
                    },
                },
            },
        },
    }
    local store = makeStore(definition, { Mode = "A" })
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertTrue(imgui._state.newLineCalls >= 2)

    local first0 = nil
    local first80 = nil
    local second0 = nil
    local second80 = nil
    for _, x in ipairs(imgui._state.setCursorPosXCalls) do
        if x == 0 then
            if first0 == nil then
                first0 = true
            else
                second0 = true
            end
        elseif x == 80 then
            if first80 == nil then
                first80 = true
            else
                second80 = true
            end
        end
    end
    lu.assertTrue(first0)
    lu.assertTrue(first80)
    lu.assertTrue(second0)
    lu.assertTrue(second80)
end

function TestUiNodes:testPackedCheckboxListCanUseDeclaredItemSlots()
    local definition = {
        storage = {
            {
                type = "packedInt",
                alias = "PackedFlags",
                configKey = "PackedFlags",
                bits = {
                    { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false },
                    { alias = "FlagB", offset = 1, width = 1, type = "bool", default = false },
                },
            },
        },
        ui = {
            {
                type = "packedCheckboxList",
                binds = { value = "PackedFlags" },
                slotCount = 4,
                geometry = {
                    slots = {
                        { name = "item:1", line = 1, start = 0 },
                        { name = "item:2", line = 1, start = 80 },
                        { name = "item:3", line = 2, start = 0 },
                        { name = "item:4", line = 2, start = 80 },
                    },
                },
            },
        },
    }
    local store = makeStore(definition, { PackedFlags = 0 })
    local imgui = makeBasicImgui()
    local checkboxCalls = 0
    imgui.Checkbox = function(_, _, current)
        checkboxCalls = checkboxCalls + 1
        return current, false
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(imgui._state.newLineCalls, 0)
    lu.assertEquals(checkboxCalls, 2)

    local first0 = nil
    local first80 = nil
    for _, x in ipairs(imgui._state.setCursorPosXCalls) do
        if x == 0 then
            first0 = true
        elseif x == 80 then
            first80 = true
        end
    end
    lu.assertTrue(first0)
    lu.assertTrue(first80)
end

function TestUiNodes:testDrawUiNodeCanApplyRuntimeSlotGeometryOverrides()
    local definition = {
        storage = {
            { type = "string", alias = "Mode", configKey = "Mode", default = "A" },
        },
        ui = {
            {
                type = "radio",
                binds = { value = "Mode" },
                values = { "A", "B", "C" },
            },
        },
    }
    local store = makeStore(definition, { Mode = "A" })
    local imgui = makeBasicImgui()
    local radioCalls = 0
    imgui.RadioButton = function()
        radioCalls = radioCalls + 1
        return false
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState, nil, nil, {
        slots = {
            { name = "option:1", line = 1, start = 0 },
            { name = "option:2", hidden = true },
            { name = "option:3", line = 1, start = 80 },
        },
    })

    lu.assertFalse(changed)
    lu.assertEquals(radioCalls, 2)
    lu.assertEquals(imgui._state.newLineCalls, 0)

    local saw0 = false
    local saw80 = false
    for _, x in ipairs(imgui._state.setCursorPosXCalls) do
        if x == 0 then
            saw0 = true
        elseif x == 80 then
            saw80 = true
        end
    end
    lu.assertTrue(saw0)
    lu.assertTrue(saw80)
end
