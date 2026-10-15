local lu = require("luaunit")
local createLibHarness = require("tests/harness/create_lib_harness")
local fakeEngine = require("tests/harness/fake_engine")

-- `module.ui.tabs(...)` / `module.ui.header(...)`: declaration validation and how the shared module
-- frame draws and commits them in pack and fallback modes.
TestModuleTabs = {}

local ATTENTION = { 0.90, 0.75, 0.20, 1.0 }
local MUTED = { 0.60, 0.60, 0.65, 1.0 }

-- ImGui stub recording the frame's draw order, tab labels and text colour pushes.
local function createImgui()
    local log = {}
    local state = {
        selected = nil, -- nil: every tab reports selected; otherwise the one label that does.
        clicks = {},
        pushDepth = 0,
    }
    local function noop() end
    local function record(entry)
        log[#log + 1] = entry
    end
    local imgui = {
        Checkbox = function(label, current)
            record("checkbox:" .. label)
            local value = state.clicks[label]
            if value ~= nil then
                state.clicks[label] = nil
                return value, true
            end
            return current, false
        end,
        MenuItem = function(label)
            if state.clicks[label] == true then
                state.clicks[label] = nil
                return true
            end
            return false
        end,
        BeginTabBar = function()
            record("tabbar")
            return true
        end,
        EndTabBar = function()
            record("endtabbar")
        end,
        BeginTabItem = function(label)
            record("tab:" .. label)
            return state.selected == nil or state.selected == label
        end,
        EndTabItem = noop,
        PushStyleColor = function(id, r, g, b, a)
            state.pushDepth = state.pushDepth + 1
            record({ push = id, color = { r, g, b, a } })
        end,
        PopStyleColor = function(count)
            state.pushDepth = state.pushDepth - (count or 1)
            record("pop")
        end,
        Text = function(text)
            record("text:" .. text)
        end,
        TextColored = noop,
        TextDisabled = noop,
        Button = function()
            return false
        end,
        IsItemHovered = function()
            return false
        end,
        SetTooltip = noop,
        SameLine = noop,
        Spacing = noop,
        Separator = noop,
        AlignTextToFramePadding = noop,
        Begin = function()
            return true, true
        end,
        End = noop,
        SetNextWindowSize = noop,
        GetCursorPosX = function()
            return 0
        end,
        SetCursorPosX = noop,
    }
    local controller = { state = state }
    function controller.reset()
        for index = #log, 1, -1 do
            log[index] = nil
        end
    end
    function controller.log()
        return log
    end
    -- Entries between the frame's BeginTabBar and EndTabBar (excludes the fallback window theme).
    function controller.tabBarLog()
        local out = {}
        local inside = false
        for _, entry in ipairs(log) do
            if entry == "endtabbar" then
                inside = false
            end
            if inside then
                out[#out + 1] = entry
            end
            if entry == "tabbar" then
                inside = true
            end
        end
        return out
    end
    -- Log entries that are strings with `prefix`, prefix kept.
    function controller.entries(prefix)
        local out = {}
        for _, entry in ipairs(log) do
            if type(entry) == "string" and string.sub(entry, 1, #prefix) == prefix then
                out[#out + 1] = entry
            end
        end
        return out
    end
    return imgui, controller
end

local function createHarness()
    local imgui, controller = createImgui()
    local callbacks = fakeEngine.createCallbacks()
    local h = createLibHarness({
        callbacks = callbacks,
        rom = {
            ImGui = imgui,
            ImGuiKey = {},
            gui = {
                is_open = function()
                    return false
                end,
            },
        },
        config = { DebugMode = false },
    })
    h.imgui = controller
    h.warnings = {}
    h.env.print = function(message)
        h.warnings[#h.warnings + 1] = message
    end
    return h
end

local STORAGE = {
    { type = "bool", alias = "HeaderFlag", default = false },
    { type = "bool", alias = "TabFlag", default = false },
}

local function newModule(h, guid, opts)
    opts = opts or {}
    h:writeNativeConfig(guid, opts.config or { Enabled = true })
    local module = assert(h.public.createModule({
        pluginGuid = guid,
        id = opts.id or guid:gsub("[^%w]", ""),
        name = guid,
    }))
    module.data.define(STORAGE)
    return module
end

local function live(h, guid)
    return h.moduleRegistry.getLiveModule(guid)
end

local function tabLabel(owner, id, label)
    return "tab:" .. label .. "###tab-" .. owner .. "-" .. id
end

local function libTabLabel(owner)
    return "tab:Advanced###advanced-" .. owner
end

-- A tabs module with a header: the header and the "beta" tab stage writes; tab states are read
-- from `states` each frame.
local function createTabsModule(h, guid, opts)
    opts = opts or {}
    local module = newModule(h, guid, opts)
    local calls = { commits = 0, header = 0, alpha = 0, beta = 0 }
    local states = { alpha = nil, beta = nil }
    if opts.fallbackWindow then
        module.fallbackUi.attachGuiOnce(function(registered)
            calls.bridge = registered
        end)
    end
    module.onCommit(function()
        calls.commits = calls.commits + 1
    end)
    module.ui.header(function(_, ui)
        calls.header = calls.header + 1
        ui.draw.imgui.Text("header")
        if calls.writeHeader then
            ui.data.write("HeaderFlag", true)
        end
    end)
    module.ui.tabs({
        {
            id = "alpha",
            label = "Alpha",
            draw = function(_, ui)
                calls.alpha = calls.alpha + 1
                ui.draw.imgui.Text("alpha")
            end,
            state = function()
                return states.alpha
            end,
        },
        {
            id = "beta",
            label = "Beta",
            draw = function(_, ui)
                calls.beta = calls.beta + 1
                ui.draw.imgui.Text("beta")
                if calls.writeTab then
                    ui.data.write("TabFlag", true)
                end
            end,
            state = function()
                return states.beta
            end,
        },
        { id = "gamma", label = "Gamma", draw = function() end },
    })
    assert(module.activate())
    return module, calls, states
end

-- Pack mode: the modpack module page (`module_tabs.lua`) with a runtime whose commitEntryState
-- commits the live module like the real one does.
local function createPackPage(h, guid)
    local entry = { id = "PackEntry", pluginGuid = guid, tooltip = "" }
    local staging = { modules = { PackEntry = true }, debug = { PackEntry = false } }
    local pack = { commitEntryStates = 0 }
    local drawPage = h.import("core/modpack/ui/module_tabs.lua", nil, {
        rom = h.rom,
        createModuleFrame = h.imports["core/ui/module_frame.lua"],
        moduleRegistry = { snapshot = {} },
        staging = staging,
        runtime = {
            toggleEntry = function(_, enabled)
                staging.modules.PackEntry = enabled
                return true
            end,
            commitEntryState = function()
                pack.commitEntryStates = pack.commitEntryStates + 1
                assert(live(h, guid).commitIfDirty())
            end,
            resyncEntry = function() end,
        },
        snapshotAccess = {
            getLiveModule = function()
                return live(h, guid)
            end,
        },
    })
    function pack.draw()
        h.imgui.reset()
        drawPage(entry, {})
    end
    pack.staging = staging
    return pack
end

local function createFallbackWindow(h, calls)
    h.imgui.state.clicks["Show Mod Menu"] = true
    calls.bridge.addMenuBar()
    return {
        draw = function()
            h.imgui.reset()
            calls.bridge.renderWindow()
        end,
    }
end

local function modeDrivers(h)
    local packModule, packCalls, packStates = createTabsModule(h, "pack-tabs")
    local fallbackModule, fallbackCalls, fallbackStates = createTabsModule(h, "fallback-tabs", {
        fallbackWindow = true,
    })
    return {
        {
            name = "pack",
            owner = "pack-tabs",
            module = packModule,
            calls = packCalls,
            states = packStates,
            page = createPackPage(h, "pack-tabs"),
        },
        {
            name = "fallback",
            owner = "fallback-tabs",
            module = fallbackModule,
            calls = fallbackCalls,
            states = fallbackStates,
            page = createFallbackWindow(h, fallbackCalls),
        },
    }
end

-- -----------------------------------------------------------------------------
-- Declaration validation
-- -----------------------------------------------------------------------------

local function validTabs()
    return {
        { id = "one", label = "One", draw = function() end },
    }
end

function TestModuleTabs:testTabsRejectsInvalidDeclarations()
    local h = createHarness()
    local cases = {
        { value = nil, message = "non-empty list of tabs" },
        { value = {}, message = "non-empty list of tabs" },
        { value = { { id = "one", label = "One", draw = function() end }, extra = true }, message = "unexpected key 'extra'" },
        { value = { "nope" }, message = "module.ui.tabs #1 must be a table" },
        { value = { { id = "1bad", label = "One", draw = function() end } }, message = "module.ui.tabs #1 id '1bad' must start with a letter" },
        { value = { { label = "One", draw = function() end } }, message = "id 'nil'" },
        { value = { { id = "one", label = "", draw = function() end } }, message = "label must be a non-empty string" },
        { value = { { id = "one", label = 3, draw = function() end } }, message = "label must be a non-empty string" },
        { value = { { id = "one", label = "One" } }, message = "draw must be a function" },
        { value = { { id = "one", label = "One", draw = function() end, state = "attention" } }, message = "state must be a function" },
        { value = { { id = "one", label = "One", draw = function() end, color = "red" } }, message = "unknown field 'color'" },
        {
            value = {
                { id = "one", label = "One", draw = function() end },
                { id = "one", label = "Again", draw = function() end },
            },
            message = "module.ui.tabs #2: duplicate tab id 'one'",
        },
    }
    for index, case in ipairs(cases) do
        local module = newModule(h, "invalid-tabs-" .. index, { id = "InvalidTabs" .. index })
        lu.assertErrorMsgContains("module.invalid_create_opts", function()
            module.ui.tabs(case.value)
        end)
        lu.assertErrorMsgContains(case.message, function()
            module.ui.tabs(case.value)
        end)
    end
end

function TestModuleTabs:testTabAndTabsAreExclusiveAndSetOnce()
    local h = createHarness()
    local tabFirst = newModule(h, "tab-first")
    tabFirst.ui.tab(function() end)
    lu.assertErrorMsgContains("module.ui.tabs cannot be combined with module.ui.tab", function()
        tabFirst.ui.tabs(validTabs())
    end)

    local tabsFirst = newModule(h, "tabs-first")
    tabsFirst.ui.tabs(validTabs())
    lu.assertErrorMsgContains("module.ui.tab cannot be combined with module.ui.tabs", function()
        tabsFirst.ui.tab(function() end)
    end)
    lu.assertErrorMsgContains("module.ui.tabs already declared", function()
        tabsFirst.ui.tabs(validTabs())
    end)

    local header = newModule(h, "header-once")
    lu.assertErrorMsgContains("module.ui.header callback must be a function", function()
        header.ui.header("nope")
    end)
    header.ui.header(function() end)
    lu.assertErrorMsgContains("module.ui.header already declared", function()
        header.ui.header(function() end)
    end)

    -- Declarations close at activation.
    header.ui.tabs(validTabs())
    lu.assertTrue(header.activate())
    lu.assertErrorMsgContains("module.ui.tabs cannot be called after module activation begins", function()
        header.ui.tabs(validTabs())
    end)
    lu.assertErrorMsgContains("module.ui.header cannot be called after module activation begins", function()
        header.ui.header(function() end)
    end)
end

function TestModuleTabs:testActivateRequiresTabOrTabs()
    local h = createHarness()
    local missing = newModule(h, "missing-tabs")
    missing.ui.header(function() end)
    local ok, err = missing.activate()
    lu.assertFalse(ok)
    lu.assertStrContains(err, "module.ui.tab or module.ui.tabs must be declared before module.activate")

    local withTabs = newModule(h, "with-tabs")
    withTabs.ui.tabs(validTabs())
    lu.assertTrue(withTabs.activate())
end

function TestModuleTabs:testTabsDeclarationIsCopied()
    local h = createHarness()
    local module = newModule(h, "copied-tabs")
    local tabs = validTabs()
    module.ui.tabs(tabs)
    tabs[1].label = "Changed"
    tabs[2] = { id = "late", label = "Late", draw = function() end }
    assert(module.activate())

    local layout = live(h, "copied-tabs").getUiLayout()
    lu.assertEquals(layout, {
        hasHeader = false,
        tabs = { { id = "one", label = "One", hasState = false } },
    })
end

-- -----------------------------------------------------------------------------
-- Frame rendering
-- -----------------------------------------------------------------------------

function TestModuleTabs:testFrameDrawsHeaderThenModuleTabsThenLibTab()
    local h = createHarness()
    for _, mode in ipairs(modeDrivers(h)) do
        local owner = mode.owner
        mode.page.draw()
        lu.assertEquals(h.imgui.entries("tab:"), {
            tabLabel(owner, "alpha", "Alpha"),
            tabLabel(owner, "beta", "Beta"),
            tabLabel(owner, "gamma", "Gamma"),
            libTabLabel(owner),
        }, mode.name)
        -- Header sits between Enabled and the tab bar; every tab reports selected in this stub.
        local order = {}
        for _, entry in ipairs(h.imgui.log()) do
            if entry == "checkbox:Enabled" or entry == "tabbar" or entry == "text:header"
                or entry == "text:alpha" or entry == "text:beta" then
                order[#order + 1] = entry
            end
        end
        lu.assertEquals(order, { "checkbox:Enabled", "text:header", "tabbar", "text:alpha", "text:beta" }, mode.name)
    end
end

function TestModuleTabs:testFrameDrawsOnlyTheActiveModuleTab()
    local h = createHarness()
    for _, mode in ipairs(modeDrivers(h)) do
        h.imgui.state.selected = string.sub(tabLabel(mode.owner, "beta", "Beta"), 5)
        mode.page.draw()
        lu.assertEquals(mode.calls.alpha, 0, mode.name)
        lu.assertEquals(mode.calls.beta, 1, mode.name)
        lu.assertEquals(mode.calls.header, 1, mode.name)
        h.imgui.state.selected = nil
    end
end

function TestModuleTabs:testTabStatesColourLabelsAroundBeginTabItem()
    local h = createHarness()
    for _, mode in ipairs(modeDrivers(h)) do
        local owner = mode.owner
        mode.states.alpha = "attention"
        mode.states.beta = "muted"
        mode.page.draw()

        local log = h.imgui.tabBarLog()
        local function indexOf(value)
            for index, entry in ipairs(log) do
                if entry == value then
                    return index
                end
            end
        end
        local alpha = indexOf(tabLabel(owner, "alpha", "Alpha"))
        local beta = indexOf(tabLabel(owner, "beta", "Beta"))
        local gamma = indexOf(tabLabel(owner, "gamma", "Gamma"))
        lu.assertEquals(log[alpha - 1], { push = 0, color = ATTENTION }, mode.name)
        lu.assertEquals(log[alpha + 1], "pop", mode.name)
        lu.assertEquals(log[beta - 1], { push = 0, color = MUTED }, mode.name)
        lu.assertEquals(log[beta + 1], "pop", mode.name)
        -- Gamma has no state callback; nothing is pushed around it or the Lib tab.
        lu.assertNotEquals(log[gamma - 1], "pop", mode.name)
        lu.assertEquals(type(log[gamma - 1]), "string", mode.name)
        lu.assertEquals(type(log[gamma + 1]), "string", mode.name)
        lu.assertEquals(h.imgui.state.pushDepth, 0, mode.name)

        -- A nil state pushes nothing.
        mode.states.alpha = nil
        mode.states.beta = nil
        mode.page.draw()
        for _, entry in ipairs(h.imgui.tabBarLog()) do
            lu.assertEquals(type(entry), "string", mode.name)
        end
    end
end

function TestModuleTabs:testInvalidTabStateIsRejected()
    local h = createHarness()
    local mode = modeDrivers(h)[1]
    mode.states.alpha = "loud"
    lu.assertErrorMsgContains("module.invalid_tab_state", mode.page.draw)
end

function TestModuleTabs:testHeaderAndActiveTabCommitOncePerFrame()
    local h = createHarness()
    for _, mode in ipairs(modeDrivers(h)) do
        h.imgui.state.selected = string.sub(tabLabel(mode.owner, "beta", "Beta"), 5)
        mode.calls.writeHeader = true
        mode.calls.writeTab = true
        mode.page.draw()
        lu.assertEquals(mode.calls.commits, 1, mode.name)
        lu.assertTrue(live(h, mode.owner).read("HeaderFlag"), mode.name)
        lu.assertTrue(live(h, mode.owner).read("TabFlag"), mode.name)
        if mode.page.commitEntryStates ~= nil then
            lu.assertEquals(mode.page.commitEntryStates, 1, mode.name)
        end

        -- Nothing staged: drawing again commits nothing new.
        mode.calls.writeHeader = false
        mode.calls.writeTab = false
        mode.page.draw()
        lu.assertEquals(mode.calls.commits, 1, mode.name)
        h.imgui.state.selected = nil
    end
end

function TestModuleTabs:testDisabledTabsModuleDrawsOnlyEnabled()
    local h = createHarness()
    for _, mode in ipairs(modeDrivers(h)) do
        h.imgui.state.clicks.Enabled = false
        mode.page.draw()
        mode.page.draw()
        lu.assertEquals(h.imgui.entries("checkbox:"), { "checkbox:Enabled" }, mode.name)
        lu.assertEquals(h.imgui.entries("tab"), {}, mode.name)
        lu.assertEquals(h.imgui.entries("text:"), {}, mode.name)
        lu.assertEquals(mode.calls.header, 0, mode.name)
        lu.assertEquals(mode.calls.alpha + mode.calls.beta, 0, mode.name)
    end
end

function TestModuleTabs:testSingleTabModuleKeepsModuleTab()
    local h = createHarness()
    local module = newModule(h, "single-tab")
    local drawn = 0
    module.fallbackUi.attachGuiOnce(function(registered)
        module.bridge = registered
    end)
    module.ui.tab(function()
        drawn = drawn + 1
    end)
    assert(module.activate())
    lu.assertEquals(live(h, "single-tab").getUiLayout(), { hasHeader = false })

    local window = createFallbackWindow(h, { bridge = module.bridge })
    window.draw()
    lu.assertEquals(h.imgui.entries("tab:"), { "tab:Module###module-single-tab", libTabLabel("single-tab") })
    lu.assertEquals(drawn, 1)
    for _, entry in ipairs(h.imgui.tabBarLog()) do
        lu.assertEquals(type(entry), "string")
    end
end

-- Callers outside the module frame (tests, tools) still draw-and-commit in one call: the header
-- and the first tab draw, then staged writes commit.
function TestModuleTabs:testDrawTabAndCommitDrawsHeaderAndFirstTabThenCommits()
    local h = createHarness()
    local _, calls = createTabsModule(h, "draw-commit-mod")
    calls.writeHeader = true
    lu.assertTrue(live(h, "draw-commit-mod").drawTabAndCommit())
    lu.assertEquals(calls.header, 1)
    lu.assertEquals(calls.alpha, 1)
    lu.assertEquals(calls.beta, 0)
    lu.assertEquals(calls.commits, 1)
    lu.assertTrue(live(h, "draw-commit-mod").read("HeaderFlag"))
end
