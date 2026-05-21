local createLibHarness = require("tests/harness/create_lib_harness")

local function createValueSession(value)
    return {
        read = function()
            return value
        end,
        write = function(_, nextValue)
            value = nextValue
        end,
        getAliasSchema = function(alias)
            return { alias = alias, type = "int" }
        end,
    }
end

local function createReadOnlySession(values)
    return {
        read = function(alias)
            return values[alias]
        end,
        getAliasSchema = function(alias)
            return { alias = alias, type = "string" }
        end,
    }
end

local function makeDropdownImgui()
    local state = {
        beginComboId = nil,
        beginComboPreview = nil,
        customPreviewCalls = 0,
        customPreviewText = nil,
        cursorX = 0,
        cursorPositions = {},
    }

    local imgui = {
        GetCursorPosX = function() return state.cursorX end,
        SetCursorPosX = function(x)
            state.cursorX = x
            state.cursorPositions[#state.cursorPositions + 1] = x
        end,
        AlignTextToFramePadding = function() end,
        Text = function(text)
            state.lastText = text
            state.cursorX = #(tostring(text or "")) * 8
        end,
        IsItemHovered = function() return false end,
        SetTooltip = function() end,
        SameLine = function() end,
        Button = function() return false end,
        Dummy = function() end,
        PushItemWidth = function() end,
        PopItemWidth = function() end,
        InputText = function(id, value, maxLen)
            state.inputText = { id = id, value = value, maxLen = maxLen }
            return value, false
        end,
        BeginCombo = function(id, preview)
            state.beginComboId = id
            state.beginComboPreview = preview
            return false
        end,
        GetWindowDrawList = function()
            state.customPreviewCalls = state.customPreviewCalls + 1
            return {}
        end,
        GetStyle = function()
            return {
                FramePadding = { x = 4, y = 3 },
                ItemInnerSpacing = { x = 4, y = 4 },
            }
        end,
        GetItemRectMin = function() return 0, 0 end,
        GetItemRectMax = function() return 200, 24 end,
        CalcTextSize = function(text) return #(tostring(text or "")) * 8, 16 end,
        GetFrameHeight = function() return 20 end,
        GetColorU32 = function() return 1 end,
        PushClipRect = function() end,
        ImDrawListAddText = function(_, _, _, _, text)
            state.customPreviewText = text
        end,
        PopClipRect = function() end,
    }

    return imgui, state
end

local function makeStepperImgui(clickedLabel)
    local clickedButtons = {}
    local imgui = makeDropdownImgui()
    imgui.Button = function(label)
        clickedButtons[#clickedButtons + 1] = label
        return label == clickedLabel
    end
    return imgui, clickedButtons
end

local function createModuleState(base, config, definition)
    local state = base.moduleState.create(config, definition)
    return state.store, state.session
end

local function createPackedDefinition(base, fields)
    fields = fields or {}
    return base.moduleHost.prepareDefinition({}, {
        modpack = fields.modpack or "test-pack",
        id = fields.id or "PackedWidgetTest",
        name = fields.name or "Packed Widget Test",
        storage = fields.storage or {
            {
                type = "packedInt",
                alias = "Packed",
                bits = {
                    { alias = "First", offset = 0, width = 1, type = "bool", default = false },
                    { alias = "Second", offset = 1, width = 1, type = "bool", default = false },
                },
            },
        },
    })
end

local function createWidgetHarness(opts)
    local base = createLibHarness(opts)
    local h = {
        harness = base,
        public = base.public,
        widgets = base.widgets,
        nav = base.nav,
        moduleHost = base.moduleHost,
        moduleState = base.moduleState,

        createValueSession = createValueSession,
        createReadOnlySession = createReadOnlySession,
        makeDropdownImgui = makeDropdownImgui,
        makeStepperImgui = makeStepperImgui,
    }

    function h.createModuleState(config, definition)
        return createModuleState(base, config, definition)
    end

    function h.prepareDefinition(fields)
        return createPackedDefinition(base, fields)
    end

    function h.createPackedSession()
        local definition = createPackedDefinition(base)
        local _, session = createModuleState(base, { Enabled = false, DebugMode = false, Packed = 0 }, definition)
        return session
    end

    return h
end

return createWidgetHarness
