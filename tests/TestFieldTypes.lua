local lu = require('luaunit')

local function makeStore(definition, config)
    config = config or {}
    return lib.createStore(config, definition), config
end

local function makeBasicImgui()
    local state = {
        buttonResponses = {},
        checkboxResponses = {},
        inputTextResponses = {},
        selectables = {},
        pushIds = {},
        cursorPosX = 0,
        cursorPosY = 0,
        setCursorPosXCalls = {},
        setCursorPosCalls = {},
        cursorEvents = {},
        pushItemWidths = {},
        sameLineCalls = 0,
        newLineCalls = 0,
        buttonLabels = {},
        inputTextCalls = {},
        textDisabledCalls = {},
        pushStyleColorCalls = {},
        popStyleColorCalls = 0,
        beginTabBars = {},
        beginTabItems = {},
        beginTabBarResponses = {},
        beginTabItemResponses = {},
        endTabItemCalls = 0,
        endTabBarCalls = 0,
        beginChildren = {},
        endChildCalls = 0,
        selectableCalls = {},
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
        Selectable = function(label, selected)
            table.insert(state.selectableCalls, { label = label, selected = selected == true })
            local nextResponse = table.remove(state.selectables, 1)
            state.cursorPosY = state.cursorPosY + 26
            return nextResponse == true
        end,
        RadioButton = function()
            local nextResponse = table.remove(state.selectables, 1)
            state.cursorPosY = state.cursorPosY + 26
            return nextResponse == true
        end,
        Text = function()
            state.cursorPosY = state.cursorPosY + 26
        end,
        TextDisabled = function(text)
            table.insert(state.textDisabledCalls, text)
            state.cursorPosY = state.cursorPosY + 26
        end,
        TextColored = function()
            state.cursorPosY = state.cursorPosY + 26
        end,
        PushStyleColor = function(...)
            table.insert(state.pushStyleColorCalls, { ... })
        end,
        PopStyleColor = function()
            state.popStyleColorCalls = state.popStyleColorCalls + 1
        end,
        CalcTextSize = function(text)
            return #(tostring(text or "")) * 8
        end,
        SameLine = function()
            state.sameLineCalls = state.sameLineCalls + 1
        end,
        NewLine = function()
            state.newLineCalls = state.newLineCalls + 1
            state.cursorPosY = state.cursorPosY + 26
        end,
        IsItemHovered = function() return false end,
        SetTooltip = function() end,
        PushItemWidth = function(a, b)
            table.insert(state.pushItemWidths, b or a)
        end,
        PopItemWidth = function() end,
        PushID = function(a, b)
            table.insert(state.pushIds, b ~= nil and b or a)
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
        GetCursorPosY = function()
            return state.cursorPosY
        end,
        GetStyle = function()
            return {
                FramePadding = { x = 4, y = 3 },
                ItemSpacing = { x = 8, y = 4 },
            }
        end,
        GetFrameHeightWithSpacing = function()
            return 26
        end,
        ImGuiCol = {
            Text = 1,
        },
        SetCursorPos = function(x, y)
            state.cursorPosX = x
            state.cursorPosY = y
            table.insert(state.setCursorPosCalls, { x = x, y = y })
            table.insert(state.cursorEvents, { kind = "xy", x = x, y = y })
        end,
        SetCursorPosX = function(x)
            state.cursorPosX = x
            table.insert(state.setCursorPosXCalls, x)
            table.insert(state.cursorEvents, { kind = "x", x = x, y = state.cursorPosY })
        end,
        SetCursorPosY = function(y)
            state.cursorPosY = y
            table.insert(state.cursorEvents, { kind = "y", x = state.cursorPosX, y = y })
        end,
        InputText = function(label, current, maxLen)
            table.insert(state.inputTextCalls, { label = label, current = current, maxLen = maxLen })
            local nextResponse = table.remove(state.inputTextResponses, 1)
            if type(nextResponse) == "table" then
                state.cursorPosY = state.cursorPosY + 26
                return nextResponse.value, nextResponse.changed == true
            end
            if nextResponse ~= nil then
                state.cursorPosY = state.cursorPosY + 26
                return nextResponse, tostring(nextResponse) ~= tostring(current or "")
            end
            state.cursorPosY = state.cursorPosY + 26
            return current, false
        end,
        Button = function(label)
            table.insert(state.buttonLabels, label)
            local nextResponse = table.remove(state.buttonResponses, 1)
            state.cursorPosY = state.cursorPosY + 26
            return nextResponse == true
        end,
        BeginTabBar = function(id)
            table.insert(state.beginTabBars, id)
            local nextResponse = table.remove(state.beginTabBarResponses, 1)
            if nextResponse ~= nil then
                return nextResponse == true
            end
            return true
        end,
        EndTabBar = function()
            state.endTabBarCalls = state.endTabBarCalls + 1
        end,
        BeginTabItem = function(label)
            table.insert(state.beginTabItems, label)
            local nextResponse = table.remove(state.beginTabItemResponses, 1)
            if nextResponse ~= nil then
                return nextResponse == true
            end
            return true
        end,
        EndTabItem = function()
            state.endTabItemCalls = state.endTabItemCalls + 1
        end,
        BeginChild = function(id, width, height, border)
            table.insert(state.beginChildren, {
                id = id,
                width = width,
                height = height,
                border = border == true,
            })
            return true
        end,
        EndChild = function()
            state.endChildCalls = state.endChildCalls + 1
        end,
    }

    return imgui
end

local function getCursorXs(imgui)
    local xs = {}
    for _, event in ipairs(imgui._state.cursorEvents or {}) do
        if type(event) == "table" and type(event.x) == "number" then
            xs[#xs + 1] = event.x
        end
    end
    return xs
end

local function sawCursorPosition(imgui, x, y)
    for _, event in ipairs(imgui._state.cursorEvents or {}) do
        if type(event) == "table" and event.kind == "xy"
            and event.x == x and event.y == y then
            return true
        end
    end
    return false
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
    lu.assertTrue(sawCursorPosition(imgui, 120, 0))
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
    lu.assertTrue(sawCursorPosition(imgui, 20, 0))
    lu.assertEquals(imgui._state.setCursorPosXCalls[1], 54)
end


function TestUiNodes:testTextWidgetRendersFromBoundStringAlias()
    local definition = {
        storage = {
            { type = "string", alias = "StatusText", lifetime = "transient", default = "" },
        },
        ui = {
            { type = "text", binds = { value = "StatusText" } },
        },
    }
    local store = makeStore(definition, {})
    local imgui = makeBasicImgui()
    local textCalls = {}
    imgui.Text = function(text) table.insert(textCalls, text) end

    store.uiState.set("StatusText", "2/5 Banned")
    lib.drawUiNode(imgui, definition.ui[1], store.uiState)
    lu.assertEquals(textCalls[1], "2/5 Banned")

    store.uiState.set("StatusText", "0/5 Banned")
    textCalls = {}
    lib.drawUiNode(imgui, definition.ui[1], store.uiState)
    lu.assertEquals(textCalls[1], "0/5 Banned")
end

function TestUiNodes:testTextWidgetFallsBackToStaticTextWhenUnbound()
    local imgui = makeBasicImgui()
    local textCalls = {}
    imgui.Text = function(text) table.insert(textCalls, text) end
    local node = { type = "text", text = "Static Label" }
    lib.prepareWidgetNode(node, "TextWidget")
    lib.drawUiNode(imgui, node, { view = {} })
    lu.assertEquals(textCalls[1], "Static Label")
end

function TestUiNodes:testButtonWidgetInvokesOnClickWithUiState()
    local definition = {
        storage = {
            { type = "bool", alias = "Triggered", lifetime = "transient", default = false },
        },
        ui = {
            {
                type = "button",
                label = "Apply",
                onClick = function(uiState)
                    uiState.set("Triggered", true)
                end,
            },
        },
    }
    local store = makeStore(definition, {})
    local imgui = makeBasicImgui()
    imgui._state.buttonResponses = { true, true }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertTrue(store.uiState.get("Triggered"))
    lu.assertStrContains(imgui._state.buttonLabels[1], "Apply")
end

function TestUiNodes:testConfirmButtonArmsAndConfirmsWithNodeLocalState()
    local definition = {
        storage = {
            { type = "bool", alias = "Triggered", lifetime = "transient", default = false },
        },
        ui = {
            {
                type = "confirmButton",
                label = "Reset",
                confirmLabel = "Confirm Reset",
                timeoutSeconds = 5,
                onConfirm = function(uiState)
                    uiState.set("Triggered", true)
                end,
            },
        },
    }
    local store = makeStore(definition, {})
    local imgui = makeBasicImgui()
    imgui._state.buttonResponses = { true, true }

    local changedArm = lib.drawUiNode(imgui, definition.ui[1], store.uiState)
    local changedConfirm = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changedArm)
    lu.assertTrue(changedConfirm)
    lu.assertTrue(store.uiState.get("Triggered"))
    lu.assertStrContains(imgui._state.buttonLabels[1], "Reset")
    lu.assertStrContains(imgui._state.buttonLabels[2], "Confirm Reset")
    lu.assertFalse(definition.ui[1]._confirmButtonState.armed == true)
end

function TestUiNodes:testConfirmButtonExpiresBackToIdle()
    local imgui = makeBasicImgui()
    local node = {
        type = "confirmButton",
        label = "Reset",
        timeoutSeconds = 5,
    }

    lib.prepareWidgetNode(node, "ConfirmButtonWidget")
    node._confirmButtonState = {
        armed = true,
        expiresAt = os.clock() - 1,
    }

    local changed = lib.drawUiNode(imgui, node, { view = {} })

    lu.assertFalse(changed)
    lu.assertFalse(node._confirmButtonState.armed == true)
    lu.assertStrContains(imgui._state.buttonLabels[1], "Reset")
end

function TestUiNodes:testInputTextWidgetWritesTransientAliasAndUsesStorageMaxLen()
    local definition = {
        storage = {
            { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 },
        },
        ui = {
            {
                type = "inputText",
                binds = { value = "FilterText" },
                label = "Filter",
                geometry = {
                    slots = {
                        { name = "control", start = 120, width = 180 },
                    },
                },
            },
        },
    }
    local store = makeStore(definition, {})
    local imgui = makeBasicImgui()
    imgui._state.inputTextResponses = {
        { value = "Apollo", changed = true },
    }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertEquals(store.uiState.get("FilterText"), "Apollo")
    lu.assertEquals(imgui._state.inputTextCalls[1].maxLen, 64)
    lu.assertTrue(sawCursorPosition(imgui, 120, 0))
    lu.assertEquals(imgui._state.pushItemWidths[1], 180)
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

function TestUiNodes:testDrawUiNodeRespectsTransientVisibleIfAlias()
    local definition = {
        storage = {
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
            { type = "bool", alias = "ShowAdvanced", lifetime = "transient", default = false },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = "ShowAdvanced" },
        },
    }
    local store = makeStore(definition, { Enabled = true })
    local imgui = makeBasicImgui()
    local checkboxCalls = 0
    imgui.Checkbox = function(_, _, current)
        checkboxCalls = checkboxCalls + 1
        return current, false
    end

    local changedHidden = lib.drawUiNode(imgui, definition.ui[1], store.uiState)
    store.uiState.set("ShowAdvanced", true)
    local changedShown = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changedHidden)
    lu.assertFalse(changedShown)
    lu.assertEquals(checkboxCalls, 1)
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

function TestUiNodes:testDrawUiNodeRespectsVisibleIfOnGroupLayout()
    local definition = {
        storage = {
            { type = "bool", alias = "ShowGroup", configKey = "ShowGroup", default = false },
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            {
                type = "group",
                visibleIf = "ShowGroup",
                children = {
                    { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
                },
            },
        },
    }
    local store = makeStore(definition, { ShowGroup = false, Enabled = true })
    local imgui = makeBasicImgui()
    local checkboxCalls = 0
    imgui.Checkbox = function(_, _, current)
        checkboxCalls = checkboxCalls + 1
        return current, false
    end

    local changedHidden = lib.drawUiNode(imgui, definition.ui[1], store.uiState)
    store.uiState.set("ShowGroup", true)
    local changedShown = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changedHidden)
    lu.assertFalse(changedShown)
    lu.assertEquals(checkboxCalls, 1)
end

function TestUiNodes:testDrawUiNodeRespectsVisibleIfOnPanelLayout()
    local definition = {
        storage = {
            { type = "bool", alias = "ShowPanel", configKey = "ShowPanel", default = false },
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            {
                type = "panel",
                visibleIf = "ShowPanel",
                columns = {
                    { name = "content", start = 0, width = 120 },
                },
                children = {
                    { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", panel = { column = "content", line = 1 } },
                },
            },
        },
    }
    local store = makeStore(definition, { ShowPanel = false, Enabled = true })
    local imgui = makeBasicImgui()
    local checkboxCalls = 0
    imgui.Checkbox = function(_, _, current)
        checkboxCalls = checkboxCalls + 1
        return current, false
    end

    local changedHidden = lib.drawUiNode(imgui, definition.ui[1], store.uiState)
    store.uiState.set("ShowPanel", true)
    local changedShown = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changedHidden)
    lu.assertFalse(changedShown)
    lu.assertEquals(checkboxCalls, 1)
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

function TestUiNodes:testCustomWidgetCanPassExplicitRowStartYToDrawWidgetSlots()
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
                        return lib.drawWidgetSlots(imgui, node, {
                            {
                                name = "decrement",
                                draw = function()
                                    imgui.Button("-")
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
                                    imgui.Button("+")
                                    return false
                                end,
                            },
                        }, 12, 48)
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
                        { name = "value", start = 20, width = 40, align = "center" },
                        { name = "increment", start = 70 },
                    },
                },
            },
        },
    }
    local store = makeStore(definition, { Count = 2 })
    local imgui = makeBasicImgui()

    lib.drawUiNode(imgui, definition.ui[1], store.uiState, nil, definition.customTypes)

    lu.assertTrue(#imgui._state.setCursorPosCalls >= 1)
    lu.assertEquals(imgui._state.setCursorPosCalls[1].x, 12)
    lu.assertEquals(imgui._state.setCursorPosCalls[1].y, 48)
end

function TestUiNodes:testWidgetHelpersExposeStructuredPositionedDrawHelper()
    local imgui = makeBasicImgui()
    local changed, endX, endY, consumedHeight = lib.WidgetHelpers.drawStructuredAt(
        imgui,
        10,
        20,
        26,
        function()
            imgui.Text("Hello")
            return true
        end)

    lu.assertTrue(changed)
    lu.assertEquals(imgui._state.setCursorPosCalls[1].x, 10)
    lu.assertEquals(imgui._state.setCursorPosCalls[1].y, 20)
    lu.assertEquals(endY, 46)
    lu.assertEquals(consumedHeight, 26)
    lu.assertEquals(type(endX), "number")
end

function TestUiNodes:testPrepareWidgetNodeCachesSlotGeometryForDirectCustomWidget()
    local customTypes = {
        widgets = {
            customBadge = {
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
        type = "customBadge",
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
            customBadge = {
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
    local nodeA = { type = "customBadge", text = "A" }
    local nodeB = { type = "customBadge", text = "B" }

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
                        panel = { column = "left", line = 1 },
                    },
                    {
                        type = "dropdown",
                        binds = { value = "ModeB" },
                        values = { "A", "B" },
                        panel = { column = "right", line = 1 },
                    },
                    {
                        type = "dropdown",
                        binds = { value = "ModeC" },
                        values = { "A", "B" },
                        panel = { column = "left", line = 2 },
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
    lu.assertEquals(imgui._state.newLineCalls, 0)

    local saw0 = false
    local saw120 = false
    for _, x in ipairs(getCursorXs(imgui)) do
        if x == 0 then
            saw0 = true
        elseif x == 120 then
            saw120 = true
        end
    end
    lu.assertTrue(saw0)
    lu.assertTrue(saw120)
end

function TestUiNodes:testPanelLayoutOptionalIdPushesScope()
    local definition = {
        storage = {
            { type = "string", alias = "ModeA", configKey = "ModeA", default = "A" },
        },
        ui = {
            {
                type = "panel",
                id = "ScopedPanel",
                columns = {
                    { name = "left", start = 0, width = 100 },
                },
                children = {
                    {
                        type = "dropdown",
                        binds = { value = "ModeA" },
                        values = { "A", "B" },
                        panel = { column = "left", line = 1 },
                    },
                },
            },
        },
    }
    local store = makeStore(definition, {
        ModeA = "A",
    })
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    local sawScopedPanel = false
    for _, id in ipairs(imgui._state.pushIds) do
        if id == "ScopedPanel" then
            sawScopedPanel = true
            break
        end
    end
    lu.assertTrue(sawScopedPanel)
end

function TestUiNodes:testHorizontalTabsTracksActiveTabKey()
    local definition = {
        ui = {
            {
                type = "horizontalTabs",
                id = "Tabs",
                children = {
                    { type = "text", text = "A", tabLabel = "First", tabId = "first" },
                    { type = "text", text = "B", tabLabel = "Second", tabId = "second" },
                },
            },
        },
    }
    lib.prepareUiNode(definition.ui[1], "HorizontalTabsTracking", {}, nil)
    local imgui = makeBasicImgui()
    imgui._state.beginTabItemResponses = { false, true }

    local changed = lib.drawUiNode(imgui, definition.ui[1], nil)

    lu.assertFalse(changed)
    lu.assertEquals(definition.ui[1]._activeTabKey, "second")
end

function TestUiNodes:testVerticalTabsCanBindActiveTab()
    local definition = {
        storage = {
            { type = "string", alias = "ActiveTab", lifetime = "transient", default = "second", maxLen = 32 },
        },
        ui = {
            {
                type = "verticalTabs",
                id = "Tabs",
                binds = { activeTab = "ActiveTab" },
                children = {
                    { type = "text", text = "A", tabLabel = "First", tabId = "first" },
                    { type = "text", text = "B", tabLabel = "Second", tabId = "second" },
                },
            },
        },
    }
    local store = makeStore(definition, {})
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(definition.ui[1]._activeTabKey, "second")
    lu.assertEquals(store.uiState.get("ActiveTab"), "second")
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
                    render = function(_, node, drawChild)
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

function TestUiNodes:testHorizontalTabsLayoutRendersOnlyActiveTabChild()
    local definition = {
        storage = {
            { type = "bool", alias = "EnabledA", configKey = "EnabledA", default = true },
            { type = "bool", alias = "EnabledB", configKey = "EnabledB", default = true },
        },
        ui = {
            {
                type = "horizontalTabs",
                id = "ExampleTabs",
                children = {
                    {
                        type = "checkbox",
                        binds = { value = "EnabledA" },
                        label = "Enabled A",
                        tabLabel = "First",
                    },
                    {
                        type = "checkbox",
                        binds = { value = "EnabledB" },
                        label = "Enabled B",
                        tabLabel = "Second",
                        tabId = "tab_b",
                    },
                },
            },
        },
    }
    local store = makeStore(definition, { EnabledA = true, EnabledB = true })
    local imgui = makeBasicImgui()
    imgui._state.beginTabItemResponses = { false, true }
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertEquals(imgui._state.beginTabBars[1], "ExampleTabs")
    lu.assertEquals(imgui._state.beginTabItems[1], "First")
    lu.assertEquals(imgui._state.beginTabItems[2], "Second##tab_b")
    lu.assertEquals(imgui._state.endTabItemCalls, 1)
    lu.assertEquals(imgui._state.endTabBarCalls, 1)
    lu.assertTrue(store.uiState.get("EnabledA"))
    lu.assertFalse(store.uiState.get("EnabledB"))
end

function TestUiNodes:testHorizontalTabsLayoutCanColorTabLabels()
    local node = {
        type = "horizontalTabs",
        id = "ExampleTabs",
        children = {
            {
                type = "text",
                text = "First",
                tabLabel = "First",
                tabLabelColor = { 0.9, 0.5, 0.2, 1 },
            },
            {
                type = "text",
                text = "Second",
                tabLabel = "Second",
            },
        },
    }
    lib.prepareUiNode(node, "HorizontalTabsColor", {})
    local imgui = makeBasicImgui()
    imgui._state.beginTabItemResponses = { false, false }

    local changed = lib.drawUiNode(imgui, node, { view = {} })

    lu.assertFalse(changed)
    lu.assertEquals(#imgui._state.pushStyleColorCalls, 1)
    lu.assertEquals(imgui._state.popStyleColorCalls, 1)
end

function TestUiNodes:testVerticalTabsLayoutSelectsAndRendersActiveChild()
    local definition = {
        storage = {
            { type = "bool", alias = "EnabledA", configKey = "EnabledA", default = true },
            { type = "bool", alias = "EnabledB", configKey = "EnabledB", default = true },
        },
        ui = {
            {
                type = "verticalTabs",
                id = "ExampleVerticalTabs",
                sidebarWidth = 220,
                children = {
                    {
                        type = "checkbox",
                        binds = { value = "EnabledA" },
                        label = "Enabled A",
                        tabLabel = "First",
                    },
                    {
                        type = "checkbox",
                        binds = { value = "EnabledB" },
                        label = "Enabled B",
                        tabLabel = "Second",
                        tabId = "tab_b",
                    },
                },
            },
        },
    }
    local store = makeStore(definition, { EnabledA = true, EnabledB = true })
    local imgui = makeBasicImgui()
    imgui._state.selectables = { false, true }
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertEquals(imgui._state.beginChildren[1].id, "ExampleVerticalTabs##tabs")
    lu.assertEquals(imgui._state.beginChildren[1].width, 220)
    lu.assertEquals(imgui._state.beginChildren[2].id, "ExampleVerticalTabs##detail")
    lu.assertEquals(imgui._state.sameLineCalls, 0)
    lu.assertEquals(imgui._state.endChildCalls, 2)
    lu.assertTrue(imgui._state.selectableCalls[1].selected)
    lu.assertFalse(imgui._state.selectableCalls[2].selected)
    lu.assertTrue(store.uiState.get("EnabledA"))
    lu.assertFalse(store.uiState.get("EnabledB"))
end

function TestUiNodes:testVerticalTabsLayoutCanColorTabLabels()
    local node = {
        type = "verticalTabs",
        id = "ExampleVerticalTabs",
        children = {
            {
                type = "text",
                text = "First",
                tabLabel = "First",
                tabLabelColor = { 0.2, 0.7, 0.3, 1 },
            },
            {
                type = "text",
                text = "Second",
                tabLabel = "Second",
            },
        },
    }
    lib.prepareUiNode(node, "VerticalTabsColor", {})
    local imgui = makeBasicImgui()
    imgui._state.selectables = { false, false }

    local changed = lib.drawUiNode(imgui, node, { view = {} })

    lu.assertFalse(changed)
    lu.assertEquals(#imgui._state.pushStyleColorCalls, 1)
    lu.assertEquals(imgui._state.popStyleColorCalls, 1)
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
    lu.assertEquals(imgui._state.sameLineCalls, 0)
    lu.assertTrue(sawCursorPosition(imgui, 232, 0))
    lu.assertEquals(imgui._state.pushItemWidths[1], 180)
end

function TestUiNodes:testDropdownCanBindIntChoiceValues()
    local definition = {
        storage = {
            { type = "int", alias = "Mode", configKey = "Mode", default = 1, min = 0, max = 3 },
        },
        ui = {
            {
                type = "dropdown",
                binds = { value = "Mode" },
                label = "Mode",
                values = { 0, 1, 2, 3 },
                displayValues = {
                    [0] = "Off",
                    [1] = "One",
                    [2] = "Two",
                    [3] = "Three",
                },
            },
        },
    }
    local store = makeStore(definition, { Mode = 1 })
    local imgui = makeBasicImgui()
    local seenPreview = nil
    imgui.BeginCombo = function(_, preview)
        seenPreview = preview
        return true
    end
    imgui.Selectable = function(label)
        return tostring(label):match("^Two##") ~= nil
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertEquals(seenPreview, "One")
    lu.assertEquals(store.uiState.get("Mode"), 2)
end

function TestUiNodes:testDropdownCanApplyValueColorsToPreviewAndOptions()
    local definition = {
        storage = {
            { type = "int", alias = "Mode", configKey = "Mode", default = 1, min = 0, max = 3 },
        },
        ui = {
            {
                type = "dropdown",
                binds = { value = "Mode" },
                values = { 0, 1, 2 },
                displayValues = { [0] = "Off", [1] = "One", [2] = "Two" },
                valueColors = {
                    [1] = { 0.1, 0.2, 0.3, 1 },
                    [2] = { 0.8, 0.7, 0.6, 1 },
                },
            },
        },
    }
    local store = makeStore(definition, { Mode = 1 })
    local imgui = makeBasicImgui()
    imgui.BeginCombo = function() return true end
    imgui.Selectable = function() return false end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(#imgui._state.pushStyleColorCalls, 3)
    lu.assertEquals(imgui._state.popStyleColorCalls, 3)
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
    local cursorXs = getCursorXs(imgui)
    lu.assertTrue(#cursorXs >= 7)
    local sawCenteredFirstValue = false
    local sawFirstValueStart = false
    local sawFirstIncrementStart = false
    local sawSeparatorStart = false
    for _, x in ipairs(cursorXs) do
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
    for _, x in ipairs(cursorXs) do
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
    local cursorXs = getCursorXs(imgui)
    for _, x in ipairs(cursorXs) do
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
    lu.assertEquals(imgui._state.newLineCalls, 0)
    lu.assertTrue(sawCursorPosition(imgui, 24, 26))
    lu.assertTrue(sawCursorPosition(imgui, 60, 26))

    local first24 = nil
    local first60 = nil
    for index, x in ipairs(getCursorXs(imgui)) do
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
    lu.assertEquals(imgui._state.newLineCalls, 0)
    lu.assertTrue(sawCursorPosition(imgui, 0, 26))
    lu.assertTrue(sawCursorPosition(imgui, 80, 26))

    local first0 = nil
    local first80 = nil
    local second0 = nil
    local second80 = nil
    for _, x in ipairs(getCursorXs(imgui)) do
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

function TestUiNodes:testRadioCanBindIntChoiceValues()
    local definition = {
        storage = {
            { type = "int", alias = "Mode", configKey = "Mode", default = 1, min = 0, max = 3 },
        },
        ui = {
            {
                type = "radio",
                binds = { value = "Mode" },
                label = "Mode",
                values = { 0, 1, 2, 3 },
                displayValues = {
                    [0] = "Off",
                    [1] = "One",
                    [2] = "Two",
                    [3] = "Three",
                },
            },
        },
    }
    local store = makeStore(definition, { Mode = 1 })
    local imgui = makeBasicImgui()
    imgui._state.selectables = { false, false, true, false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertEquals(store.uiState.get("Mode"), 2)
end

function TestUiNodes:testRadioCanApplyValueColorsToOptions()
    local definition = {
        storage = {
            { type = "int", alias = "Mode", configKey = "Mode", default = 1, min = 0, max = 3 },
        },
        ui = {
            {
                type = "radio",
                binds = { value = "Mode" },
                label = "",
                values = { 0, 1, 2 },
                displayValues = { [0] = "Off", [1] = "One", [2] = "Two" },
                valueColors = {
                    [1] = { 0.1, 0.2, 0.3, 1 },
                    [2] = { 0.8, 0.7, 0.6, 1 },
                },
            },
        },
    }
    local store = makeStore(definition, { Mode = 1 })
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(#imgui._state.pushStyleColorCalls, 2)
    lu.assertEquals(imgui._state.popStyleColorCalls, 2)
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

function TestUiNodes:testMappedDropdownCanUseCustomPreviewAndSelectionMapping()
    local definition = {
        storage = {
            { type = "int", alias = "Mask", configKey = "Mask", default = 0, min = 0, max = 7 },
        },
        ui = {
            {
                type = "mappedDropdown",
                binds = { value = "Mask" },
                label = "",
                getPreview = function(_, bound)
                    return (bound.value:get() or 0) == 0 and "None" or "Custom"
                end,
                getOptions = function(_, bound)
                    local current = bound.value:get() or 0
                    return {
                        {
                            label = "None",
                            selected = current == 0,
                            onSelect = function(_, boundValue)
                                if current ~= 0 then
                                    boundValue:set(0)
                                    return true
                                end
                                return false
                            end,
                        },
                        {
                            label = "Force",
                            selected = current == 3,
                            onSelect = function(_, boundValue)
                                if current ~= 3 then
                                    boundValue:set(3)
                                    return true
                                end
                                return false
                            end,
                        },
                    }
                end,
            },
        },
    }
    local store = makeStore(definition, { Mask = 0 })
    local imgui = makeBasicImgui()
    local seenPreview = nil
    imgui.BeginCombo = function(_, preview)
        seenPreview = preview
        return true
    end
    imgui.Selectable = function(label)
        return tostring(label):match("^Force##") ~= nil
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertEquals(seenPreview, "None")
    lu.assertEquals(store.uiState.view.Mask, 3)
end

function TestUiNodes:testPackedDropdownCanSelectSingleRemainingChild()
    local definition = {
        storage = {
            {
                type = "packedInt",
                alias = "Flags",
                configKey = "Flags",
                bits = {
                    { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false, label = "Alpha" },
                    { alias = "FlagB", offset = 1, width = 1, type = "bool", default = false, label = "Beta" },
                    { alias = "FlagC", offset = 2, width = 1, type = "bool", default = false, label = "Gamma" },
                },
            },
        },
        ui = {
            {
                type = "packedDropdown",
                binds = { value = "Flags" },
                selectionMode = "singleRemaining",
                noneLabel = "None",
                multipleLabel = "Multiple",
                displayValues = {
                    FlagA = "Alpha",
                    FlagB = "Beta",
                    FlagC = "Gamma",
                },
            },
        },
    }
    local store = makeStore(definition, { Flags = 0 })
    local imgui = makeBasicImgui()
    local seenPreview = nil
    imgui.BeginCombo = function(_, preview)
        seenPreview = preview
        return true
    end
    imgui.Selectable = function(label)
        return tostring(label):match("^Beta##") ~= nil
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertEquals(seenPreview, "None")
    lu.assertTrue(store.uiState.get("FlagA"))
    lu.assertFalse(store.uiState.get("FlagB"))
    lu.assertTrue(store.uiState.get("FlagC"))
end

function TestUiNodes:testPackedRadioCanSelectSingleEnabledChild()
    local definition = {
        storage = {
            {
                type = "packedInt",
                alias = "Flags",
                configKey = "Flags",
                bits = {
                    { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false, label = "Alpha" },
                    { alias = "FlagB", offset = 1, width = 1, type = "bool", default = false, label = "Beta" },
                },
            },
        },
        ui = {
            {
                type = "packedRadio",
                binds = { value = "Flags" },
                label = "",
                displayValues = {
                    FlagA = "Alpha",
                    FlagB = "Beta",
                },
            },
        },
    }
    local store = makeStore(definition, { Flags = 0 })
    local imgui = makeBasicImgui()
    imgui._state.selectables = {}
    imgui.RadioButton = function(label)
        return label == "Beta"
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertFalse(store.uiState.get("FlagA"))
    lu.assertTrue(store.uiState.get("FlagB"))
end

function TestUiNodes:testMappedRadioCanUseCustomSelectionMapping()
    local definition = {
        storage = {
            { type = "int", alias = "Mask", configKey = "Mask", default = 0, min = 0, max = 7 },
        },
        ui = {
            {
                type = "mappedRadio",
                binds = { value = "Mask" },
                label = "",
                getOptions = function(_, bound)
                    local current = bound.value:get() or 0
                    return {
                        {
                            label = "None",
                            selected = current == 0,
                            onSelect = function(_, boundValue)
                                if current ~= 0 then
                                    boundValue:set(0)
                                    return true
                                end
                                return false
                            end,
                        },
                        {
                            label = "Force",
                            selected = current == 3,
                            onSelect = function(_, boundValue)
                                if current ~= 3 then
                                    boundValue:set(3)
                                    return true
                                end
                                return false
                            end,
                        },
                    }
                end,
            },
        },
    }
    local store = makeStore(definition, { Mask = 0 })
    local imgui = makeBasicImgui()
    imgui._state.selectables = { false, true }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertEquals(store.uiState.view.Mask, 3)
end

function TestUiNodes:testStepperCanDisplayEnumLabelsAndColors()
    local definition = {
        storage = {
            { type = "int", alias = "Rarity", configKey = "Rarity", default = 2, min = 0, max = 3 },
        },
        ui = {
            {
                type = "stepper",
                binds = { value = "Rarity" },
                label = "Rarity",
                min = 0,
                max = 3,
                displayValues = {
                    [0] = "Common",
                    [1] = "Rare",
                    [2] = "Epic",
                    [3] = "Heroic",
                },
                valueColors = {
                    [2] = { 0.7, 0.2, 0.9, 1 },
                },
            },
        },
    }
    local store = makeStore(definition, { Rarity = 2 })
    local imgui = makeBasicImgui()
    local seenColored = nil
    imgui.TextColored = function(r, g, b, a, text)
        seenColored = { r, g, b, a, text }
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertNotNil(seenColored)
    lu.assertEquals(seenColored[5], "Epic")
    lu.assertAlmostEquals(seenColored[1], 0.7)
    lu.assertAlmostEquals(seenColored[2], 0.2)
    lu.assertAlmostEquals(seenColored[3], 0.9)
    lu.assertAlmostEquals(seenColored[4], 1)
end

function TestUiNodes:testPackedCheckboxListRendersAllItemsWithEmptyFilter()
    local definition = {
        storage = {
            {
                type = "packedInt",
                alias = "Flags",
                configKey = "Flags",
                bits = {
                    { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false, label = "Alpha" },
                    { alias = "FlagB", offset = 1, width = 1, type = "bool", default = false, label = "Beta" },
                    { alias = "FlagC", offset = 2, width = 1, type = "bool", default = false, label = "Gamma" },
                },
            },
            { type = "string", alias = "Filter", configKey = "Filter", default = "" },
        },
        ui = {
            {
                type = "packedCheckboxList",
                binds = { value = "Flags", filterText = "Filter" },
            },
        },
    }
    local store = makeStore(definition, { Flags = 0, Filter = "" })
    local imgui = makeBasicImgui()
    local checkboxLabels = {}
    imgui.Checkbox = function(label, current)
        checkboxLabels[#checkboxLabels + 1] = label
        return current, false
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(#checkboxLabels, 3)
    lu.assertEquals(checkboxLabels[1], "Alpha")
    lu.assertEquals(checkboxLabels[2], "Beta")
    lu.assertEquals(checkboxLabels[3], "Gamma")
end

function TestUiNodes:testPackedCheckboxListFiltersItemsByLabelSubstring()
    local definition = {
        storage = {
            {
                type = "packedInt",
                alias = "Flags",
                configKey = "Flags",
                bits = {
                    { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false, label = "Alpha" },
                    { alias = "FlagB", offset = 1, width = 1, type = "bool", default = false, label = "Citrus" },
                    { alias = "FlagC", offset = 2, width = 1, type = "bool", default = false, label = "Gamma" },
                },
            },
            { type = "string", alias = "Filter", configKey = "Filter", default = "" },
        },
        ui = {
            {
                type = "packedCheckboxList",
                binds = { value = "Flags", filterText = "Filter" },
            },
        },
    }
    local store = makeStore(definition, { Flags = 0, Filter = "a" })
    local imgui = makeBasicImgui()
    local checkboxLabels = {}
    imgui.Checkbox = function(label, current)
        checkboxLabels[#checkboxLabels + 1] = label
        return current, false
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(#checkboxLabels, 2)
    lu.assertEquals(checkboxLabels[1], "Alpha")
    lu.assertEquals(checkboxLabels[2], "Gamma")
end

function TestUiNodes:testPackedCheckboxListFiltersItemsByCheckedState()
    local definition = {
        storage = {
            {
                type = "packedInt",
                alias = "Flags",
                configKey = "Flags",
                bits = {
                    { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false, label = "Alpha" },
                    { alias = "FlagB", offset = 1, width = 1, type = "bool", default = false, label = "Beta" },
                    { alias = "FlagC", offset = 2, width = 1, type = "bool", default = false, label = "Gamma" },
                },
            },
            { type = "string", alias = "FilterMode", configKey = "FilterMode", default = "all" },
        },
        ui = {
            {
                type = "packedCheckboxList",
                binds = { value = "Flags", filterMode = "FilterMode" },
            },
        },
    }
    local store = makeStore(definition, { Flags = 5, FilterMode = "checked" })
    local imgui = makeBasicImgui()
    local checkboxLabels = {}
    imgui.Checkbox = function(label, current)
        checkboxLabels[#checkboxLabels + 1] = { label = label, current = current }
        return current, false
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(#checkboxLabels, 2)
    lu.assertEquals(checkboxLabels[1].label, "Alpha")
    lu.assertEquals(checkboxLabels[2].label, "Gamma")
    lu.assertTrue(checkboxLabels[1].current)
    lu.assertTrue(checkboxLabels[2].current)
end

function TestUiNodes:testPackedCheckboxListCanApplyAliasColors()
    local definition = {
        storage = {
            {
                type = "packedInt",
                alias = "Flags",
                configKey = "Flags",
                bits = {
                    { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false, label = "Alpha" },
                    { alias = "FlagB", offset = 1, width = 1, type = "bool", default = false, label = "Beta" },
                },
            },
        },
        ui = {
            {
                type = "packedCheckboxList",
                binds = { value = "Flags" },
                valueColors = {
                    FlagB = { 0.2, 0.4, 0.6, 1 },
                },
            },
        },
    }
    local store = makeStore(definition, { Flags = 0 })
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(#imgui._state.pushStyleColorCalls, 1)
    lu.assertEquals(imgui._state.popStyleColorCalls, 1)
end

function TestUiNodes:testPackedCheckboxListRendersAllItemsWhenFilterBindIsOmitted()
    local definition = {
        storage = {
            {
                type = "packedInt",
                alias = "Flags",
                configKey = "Flags",
                bits = {
                    { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false, label = "Alpha" },
                    { alias = "FlagB", offset = 1, width = 1, type = "bool", default = false, label = "Beta" },
                    { alias = "FlagC", offset = 2, width = 1, type = "bool", default = false, label = "Gamma" },
                },
            },
        },
        ui = {
            {
                type = "packedCheckboxList",
                binds = { value = "Flags" },
            },
        },
    }
    local store = makeStore(definition, { Flags = 0 })
    local imgui = makeBasicImgui()
    local checkboxLabels = {}
    imgui.Checkbox = function(label, current)
        checkboxLabels[#checkboxLabels + 1] = label
        return current, false
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(#checkboxLabels, 3)
    lu.assertEquals(checkboxLabels[1], "Alpha")
    lu.assertEquals(checkboxLabels[2], "Beta")
    lu.assertEquals(checkboxLabels[3], "Gamma")
end

function TestUiNodes:testPackedCheckboxListDoesNotRenderItsOwnFilterInput()
    local definition = {
        storage = {
            {
                type = "packedInt",
                alias = "Flags",
                configKey = "Flags",
                bits = {
                    { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false, label = "Alpha" },
                },
            },
            { type = "string", alias = "Filter", configKey = "Filter", default = "" },
        },
        ui = {
            {
                type = "packedCheckboxList",
                binds = { value = "Flags", filterText = "Filter" },
            },
        },
    }
    local store = makeStore(definition, { Flags = 0, Filter = "" })
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(#imgui._state.inputTextCalls, 0)
end

function TestUiNodes:testPackedCheckboxListCheckboxChangeMarksChanged()
    local definition = {
        storage = {
            {
                type = "packedInt",
                alias = "Flags",
                configKey = "Flags",
                bits = {
                    { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false, label = "Alpha" },
                    { alias = "FlagB", offset = 1, width = 1, type = "bool", default = false, label = "Beta" },
                },
            },
            { type = "string", alias = "Filter", configKey = "Filter", default = "" },
        },
        ui = {
            {
                type = "packedCheckboxList",
                binds = { value = "Flags", filterText = "Filter" },
            },
        },
    }
    local store = makeStore(definition, { Flags = 0, Filter = "" })
    local imgui = makeBasicImgui()
    imgui._state.checkboxResponses = { true }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertTrue(store.uiState.get("FlagA"))
    lu.assertFalse(store.uiState.get("FlagB"))
end

function TestUiNodes:testPackedCheckboxListGeometryCompactsVisibleItemsIntoItemSlots()
    local definition = {
        storage = {
            {
                type = "packedInt",
                alias = "Flags",
                configKey = "Flags",
                bits = {
                    { alias = "FlagA", offset = 0, width = 1, type = "bool", default = false, label = "Alpha" },
                    { alias = "FlagB", offset = 1, width = 1, type = "bool", default = false, label = "Beta" },
                    { alias = "FlagC", offset = 2, width = 1, type = "bool", default = false, label = "Gamma" },
                },
            },
            { type = "string", alias = "Filter", configKey = "Filter", default = "" },
        },
        ui = {
            {
                type = "packedCheckboxList",
                binds = { value = "Flags", filterText = "Filter" },
                slotCount = 2,
                geometry = {
                    slots = {
                        { name = "item:1", line = 1, start = 24 },
                        { name = "item:2", line = 2, start = 60 },
                    },
                },
            },
        },
    }
    local store = makeStore(definition, { Flags = 0, Filter = "a" })
    local imgui = makeBasicImgui()

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
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
