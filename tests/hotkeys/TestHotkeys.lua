local lu = require("luaunit")
local createLibHarness = require("tests/harness/create_lib_harness")
local fakeEngine = require("tests/harness/fake_engine")

TestHotkeys = {}

local KEY_CODES = {
    LeftCtrl = 100,
    RightCtrl = 101,
    LeftShift = 102,
    RightShift = 103,
    LeftAlt = 104,
    RightAlt = 105,
}
for number = 1, 12 do
    KEY_CODES["F" .. number] = number
end

-- ImGui stub that records draw calls and lets a test press keys and click combo entries.
local function createImgui()
    local input = {
        pressed = {},
        down = {},
        pressedCalls = 0,
    }
    local drawn = {
        texts = {},
        colored = {},
        combos = {},
        headers = {},
        windows = {},
        checkboxes = {},
    }
    local clicks = {}
    local openCombo = nil
    local nextItemOpen = nil
    local function noop() end

    local imgui = {
        IsKeyPressed = function(code, repeating)
            input.pressedCalls = input.pressedCalls + 1
            lu.assertFalse(repeating)
            return input.pressed[code] == true
        end,
        IsKeyDown = function(code)
            return input.down[code] == true
        end,
        AlignTextToFramePadding = noop,
        Text = function(text)
            drawn.texts[#drawn.texts + 1] = text
        end,
        TextColored = function(_, _, _, _, text)
            drawn.colored[#drawn.colored + 1] = text
        end,
        SameLine = noop,
        Spacing = noop,
        Separator = noop,
        IsItemHovered = function()
            return false
        end,
        SetTooltip = noop,
        PushItemWidth = noop,
        PopItemWidth = noop,
        BeginCombo = function(id, preview)
            drawn.combos[#drawn.combos + 1] = { id = id, preview = preview }
            if clicks[id] ~= nil then
                openCombo = id
                return true
            end
            return false
        end,
        Selectable = function(label)
            if openCombo ~= nil and clicks[openCombo] == label then
                clicks[openCombo] = nil
                return true
            end
            return false
        end,
        EndCombo = function()
            openCombo = nil
        end,
        Button = function(label)
            if clicks[label] == true then
                clicks[label] = nil
                return true
            end
            return false
        end,
        MenuItem = function(label)
            if clicks[label] == true then
                clicks[label] = nil
                return true
            end
            return false
        end,
        -- ImGui semantics: SetNextItemOpen sets the header state, a click toggles it.
        SetNextItemOpen = function(open)
            nextItemOpen = open
        end,
        CollapsingHeader = function(label)
            drawn.headers[#drawn.headers + 1] = label
            local open = nextItemOpen == true
            nextItemOpen = nil
            if clicks[label] == true then
                clicks[label] = nil
                open = not open
            end
            return open
        end,
        Checkbox = function(label, current)
            drawn.checkboxes[#drawn.checkboxes + 1] = label
            return current, false
        end,
        Begin = function(title)
            drawn.windows[#drawn.windows + 1] = title
            return true, true
        end,
        End = noop,
        SetNextWindowSize = noop,
        PushStyleColor = noop,
        PopStyleColor = noop,
        GetCursorPosX = function()
            return 0
        end,
        SetCursorPosX = noop,
    }

    local controller = {
        input = input,
        drawn = drawn,
    }
    function controller.clickCombo(id, label)
        clicks[id] = label
    end
    function controller.clickButton(label)
        clicks[label] = true
    end
    controller.clickHeader = controller.clickButton
    controller.clickMenuItem = controller.clickButton
    function controller.resetDrawn()
        drawn.texts = {}
        drawn.colored = {}
        drawn.combos = {}
        drawn.headers = {}
        drawn.windows = {}
        drawn.checkboxes = {}
    end
    function controller.comboPreview(id)
        for _, combo in ipairs(drawn.combos) do
            if combo.id == id then
                return combo.preview
            end
        end
        return nil
    end
    return imgui, controller
end

local function createHarness(opts)
    opts = opts or {}
    local imgui, controller = createImgui()
    local guiState = { open = false }
    local callbacks = opts.callbacks or fakeEngine.createCallbacks()
    local rom = opts.rom or {
        ImGui = imgui,
        ImGuiKey = KEY_CODES,
        gui = {
            is_open = function()
                return guiState.open
            end,
        },
    }
    local h = createLibHarness({
        callbacks = callbacks,
        rom = rom,
        runtime = opts.runtime,
        config = opts.config or { DebugMode = false },
        nativeConfigRoot = opts.nativeConfigRoot,
    })
    h.callbacks = callbacks
    h.imgui = controller
    h.guiState = guiState
    h.hotkeys = h.imports["core/hotkeys/00_init.lua"]
    h.warnings = {}
    h.env.print = function(message)
        h.warnings[#h.warnings + 1] = message
    end
    return h
end

local function tick(h)
    fakeEngine.runAlwaysDraw(h.callbacks)
end

local function press(h, keyName, modifiers)
    local input = h.imgui.input
    input.pressed = { [KEY_CODES[keyName]] = true }
    input.down = {}
    for _, modifier in ipairs(modifiers or {}) do
        input.down[KEY_CODES[modifier]] = true
    end
    tick(h)
    input.pressed = {}
    input.down = {}
end

-- Creates and activates one module. `requests` is a list of { id, opts }.
local function createModule(h, opts)
    h:writeNativeConfig(opts.guid, opts.config or { Enabled = true })
    local module = assert(h.public.createModule({
        pluginGuid = opts.guid,
        modpack = opts.modpack,
        id = opts.id or opts.guid:gsub("[^%w]", ""),
        name = opts.name or opts.guid,
    }))
    if opts.storage ~= nil then
        module.data.define(opts.storage)
    end
    for _, request in ipairs(opts.requests or {}) do
        module.hotkeys.request(request[1], request[2])
    end
    if opts.onActivate ~= nil then
        module.onActivate(opts.onActivate)
    end
    local bridge = nil
    if opts.fallbackWindow then
        module.fallbackUi.attachGuiOnce(function(registered)
            bridge = registered
        end)
    end
    module.ui.tab(opts.drawTab or function() end)
    local ok, err = module.activate()
    return module, ok, err, bridge
end

local function live(h, guid)
    return h.moduleRegistry.getLiveModule(guid)
end

local function counter()
    local calls = { count = 0 }
    calls.onPress = function(host, runtime)
        calls.count = calls.count + 1
        calls.host = host
        calls.runtime = runtime
    end
    return calls
end

local function request(id, label, default, onPress, extra)
    local opts = {
        label = label,
        default = default,
        onPress = onPress,
    }
    for key, value in pairs(extra or {}) do
        opts[key] = value
    end
    return { id, opts }
end

local function status(h, guid, id)
    return h.hotkeys.status(guid, id)
end

-- -----------------------------------------------------------------------------
-- Bindings
-- -----------------------------------------------------------------------------

function TestHotkeys:testBindingParsingAcceptsCanonicalForms()
    local h = createHarness()
    local bindings = h.imports["core/hotkeys/bindings.lua"]

    local parsed = bindings.parse("Ctrl+Shift+F5")
    lu.assertEquals(parsed.key, "F5")
    lu.assertTrue(parsed.ctrl)
    lu.assertTrue(parsed.shift)
    lu.assertFalse(parsed.alt)
    lu.assertEquals(parsed.prefix, "Ctrl+Shift+")
    lu.assertIs(bindings.parse("Ctrl+Shift+F5"), parsed)

    lu.assertEquals(bindings.parse("F12").keyIndex, 12)
    lu.assertEquals(bindings.parse("Ctrl+Shift+Alt+F1").prefix, "Ctrl+Shift+Alt+")
    lu.assertNil(bindings.parse("Ctrl+Shift+Alt+F1").modifierIndex)
    lu.assertNil(bindings.parse(""))
    lu.assertTrue(bindings.isValid(""))
    lu.assertEquals(bindings.format("Alt+", "F3"), "Alt+F3")
    lu.assertEquals(bindings.format("Alt+", nil), "")
end

function TestHotkeys:testBindingParsingRejectsNonCanonicalForms()
    local h = createHarness()
    local bindings = h.imports["core/hotkeys/bindings.lua"]

    for _, text in ipairs({ "F13", "F0", "f5", "Shift+Ctrl+F5", "Ctrl+Ctrl+F5", "Ctrl+", "+F5",
        "Ctrl++F5", "Insert", "Ctrl", "Win+F5", " F5", 5 }) do
        lu.assertNil(bindings.parse(text), tostring(text))
        lu.assertFalse(bindings.isValid(text), tostring(text))
    end
end

-- -----------------------------------------------------------------------------
-- Resolution
-- -----------------------------------------------------------------------------

function TestHotkeys:testResolutionKeepsRecordedOwnerAndClearsUnusedHistory()
    local h = createHarness()
    local resolution = h.imports["core/hotkeys/resolution.lua"]
    local history = { F9 = "b", F1 = "gone" }
    local results = resolution.resolve({
        { key = "a", binding = "F9", enabled = true },
        { key = "b", binding = "F9", enabled = true },
        { key = "c", binding = "", enabled = true },
        { key = "d", binding = "F99", enabled = true },
        { key = "e", binding = "F2", enabled = true },
        { key = "f", binding = "F3", enabled = false },
    }, history, { F2 = "test reason" })

    lu.assertEquals(results[1], { state = "conflict", ownerIndex = 2 })
    lu.assertEquals(results[2], { state = "active" })
    lu.assertEquals(results[3], { state = "unbound" })
    lu.assertEquals(results[4], { state = "invalid" })
    lu.assertEquals(results[5], { state = "reserved", reservedBy = "test reason" })
    lu.assertEquals(results[6], { state = "disabled" })
    lu.assertEquals(history, { F9 = "b" })
end

function TestHotkeys:testExistingOwnerKeepsKeyWhenAnotherModuleTakesIt()
    local h = createHarness()
    local first, second = counter(), counter()
    createModule(h, { guid = "b-mod", name = "B Mod", requests = { request("Go", "Go B", "F9", first.onPress) } })
    createModule(h, { guid = "a-mod", name = "A Mod", requests = { request("Go", "Go A", "F10", second.onPress) } })
    lu.assertEquals(status(h, "b-mod", "Go").state, "active")
    lu.assertEquals(status(h, "a-mod", "Go").state, "active")

    -- "a-mod" would win the tie-break, but "b-mod" already owns F9.
    live(h, "a-mod").writeAndFlush("Hotkey_Go", "F9")
    local conflict = status(h, "a-mod", "Go")
    lu.assertEquals(conflict.state, "conflict")
    lu.assertEquals(conflict.binding, "F9")
    lu.assertEquals(conflict.owner, { moduleName = "B Mod", label = "Go B" })
    lu.assertEquals(conflict.text, "F9 is used by B Mod (Go B); this binding is inactive")
    lu.assertEquals(status(h, "b-mod", "Go").text, "F9 - active")

    press(h, "F9")
    lu.assertEquals(first.count, 1)
    lu.assertEquals(second.count, 0)
end

function TestHotkeys:testTieBreakUsesPackOrderThenGuidThenDeclarationOrder()
    local h = createHarness()
    local calls = {}
    local function recorder(name)
        return function()
            calls[#calls + 1] = name
        end
    end
    createModule(h, { guid = "a-outside", requests = { request("Go", "Outside", "F5", recorder("outside")) } })
    createModule(h, { guid = "m-pack", requests = { request("Go", "M", "F5", recorder("m")) } })
    createModule(h, { guid = "z-pack", requests = {
        request("First", "Z first", "F6", recorder("z-first")),
        request("Second", "Z second", "F6", recorder("z-second")),
        request("Third", "Z third", "F5", recorder("z-third")),
    } })
    h.hotkeys.setPackOrder("pack", 1, { "z-pack", "m-pack" })

    lu.assertEquals(status(h, "z-pack", "Third").state, "active")
    lu.assertEquals(status(h, "m-pack", "Go").state, "conflict")
    lu.assertEquals(status(h, "a-outside", "Go").state, "conflict")
    lu.assertEquals(status(h, "z-pack", "First").state, "active")
    lu.assertEquals(status(h, "z-pack", "Second").owner, { moduleName = "z-pack", label = "Z first" })

    press(h, "F5")
    press(h, "F6")
    lu.assertEquals(calls, { "z-third", "z-first" })

    -- Without pack order the GUID decides; pushing a new order lets the tie-break decide again.
    h.hotkeys.setPackOrder("pack", 1, { "m-pack", "z-pack" })
    lu.assertEquals(status(h, "m-pack", "Go").state, "active")
    lu.assertEquals(status(h, "z-pack", "Third").state, "conflict")
end

function TestHotkeys:testUnchangedPackOrderKeepsOwnership()
    local h = createHarness()
    createModule(h, { guid = "a-mod", requests = { request("Go", "A", "F7", function() end) } })
    createModule(h, { guid = "b-mod", requests = { request("Go", "B", "F8", function() end) } })
    h.hotkeys.setPackOrder("pack", 1, { "a-mod", "b-mod" })
    live(h, "b-mod").writeAndFlush("Hotkey_Go", "F7")
    live(h, "a-mod").setEnabled(false)
    lu.assertEquals(status(h, "b-mod", "Go").state, "active")
    live(h, "a-mod").setEnabled(true)
    h.hotkeys.setPackOrder("pack", 1, { "a-mod", "b-mod" })

    lu.assertEquals(status(h, "b-mod", "Go").state, "active")
    lu.assertEquals(status(h, "a-mod", "Go").state, "conflict")
end

function TestHotkeys:testDisabledModuleDropsCandidacyAndOwnerHandsOver()
    local h = createHarness()
    local owner, other = counter(), counter()
    createModule(h, { guid = "a-mod", requests = { request("Go", "A", "F9", owner.onPress) } })
    createModule(h, { guid = "b-mod", requests = { request("Go", "B", "F9", other.onPress) } })
    lu.assertEquals(status(h, "b-mod", "Go").state, "conflict")

    live(h, "a-mod").setEnabled(false)
    lu.assertEquals(status(h, "a-mod", "Go").state, "disabled")
    lu.assertEquals(status(h, "a-mod", "Go").text, "F9 - inactive while the module is disabled")
    lu.assertEquals(status(h, "b-mod", "Go").state, "active")
    press(h, "F9")
    lu.assertEquals(owner.count, 0)
    lu.assertEquals(other.count, 1)

    -- The returning module does not take the key back.
    live(h, "a-mod").setEnabled(true)
    lu.assertEquals(status(h, "a-mod", "Go").state, "conflict")
    lu.assertEquals(status(h, "b-mod", "Go").state, "active")
end

function TestHotkeys:testReservedInvalidAndUnboundStates()
    local h = createHarness({ config = { DebugMode = false, ReservedHotkeys = "Ctrl+F4, F13 ,," } })
    local calls = counter()
    createModule(h, { guid = "a-mod", requests = {
        request("Reserved", "Reserved", "Ctrl+F4", calls.onPress),
        request("Unbound", "Unbound", nil, calls.onPress),
        request("Invalid", "Invalid", "F2", calls.onPress),
    } })
    live(h, "a-mod").writeAndFlush("Hotkey_Invalid", "Ctrl+F13")

    local reservedStatus = status(h, "a-mod", "Reserved")
    lu.assertEquals(reservedStatus.state, "reserved")
    lu.assertEquals(reservedStatus.text, "Ctrl+F4 is reserved (reserved in Lib config)")
    lu.assertEquals(status(h, "a-mod", "Unbound").state, "unbound")
    lu.assertEquals(status(h, "a-mod", "Unbound").text, "Not bound")
    lu.assertEquals(status(h, "a-mod", "Invalid").state, "invalid")
    lu.assertEquals(h.hotkeys.getReserved().manual, { "Ctrl+F4", "F13" })

    press(h, "F4", { "LeftCtrl" })
    lu.assertEquals(calls.count, 0)

    -- Editing the manual list releases the key on the next refresh.
    h.hotkeys.setManualReserved({})
    lu.assertEquals(h.config.ReservedHotkeys, "")
    lu.assertEquals(status(h, "a-mod", "Reserved").state, "active")
    press(h, "F4", { "RightCtrl" })
    lu.assertEquals(calls.count, 1)
end

function TestHotkeys:testDetectedHell2ModdingKeyIsReserved()
    local h = createHarness()
    local file = assert(io.open(h.nativeConfigRoot .. "/Hell2Modding-Hell2Modding-Hotkeys.cfg", "w"))
    file:write("[Hotkeys]\n\n# Setting type: string\ngui_toggle = 'VK_F3'\n")
    file:close()
    createModule(h, { guid = "a-mod", requests = { request("Go", "Go", "F3", function() end) } })

    local reservedStatus = status(h, "a-mod", "Go")
    lu.assertEquals(reservedStatus.state, "reserved")
    lu.assertEquals(reservedStatus.text, "F3 is reserved (Hell2Modding overlay)")
    lu.assertEquals(h.hotkeys.getReserved().detected, { raw = "VK_F3", binding = "F3" })

    os.remove(h.nativeConfigRoot .. "/Hell2Modding-Hell2Modding-Hotkeys.cfg")
    h.hotkeys.redetectReserved()
    lu.assertEquals(status(h, "a-mod", "Go").state, "active")
    lu.assertNil(h.hotkeys.getReserved().detected)
end

-- -----------------------------------------------------------------------------
-- Reserved detection parsing
-- -----------------------------------------------------------------------------

function TestHotkeys:testGuiToggleParsingAndVirtualKeyMapping()
    local h = createHarness()
    local reserved = h.imports["core/hotkeys/reserved.lua"]

    lu.assertEquals(reserved.parseGuiToggle("x = 1\ngui_toggle = 'VK_F1'\n"), "VK_F1")
    lu.assertEquals(reserved.parseGuiToggle("gui_toggle = 'VK_INSERT'"), "VK_INSERT")
    lu.assertEquals(reserved.parseGuiToggle("  gui_toggle='1'\r\n"), "1")
    lu.assertEquals(reserved.parseGuiToggle('gui_toggle = "VK_F2"'), "VK_F2")
    lu.assertEquals(reserved.parseGuiToggle("gui_toggle = VK_F4 # comment"), "VK_F4")
    lu.assertNil(reserved.parseGuiToggle("other_toggle = 'VK_F1'\n# gui_toggle = 'VK_F2'"))

    lu.assertEquals(reserved.mapVirtualKey("VK_F1"), "F1")
    lu.assertEquals(reserved.mapVirtualKey("VK_F12"), "F12")
    lu.assertNil(reserved.mapVirtualKey("VK_F13"))
    lu.assertNil(reserved.mapVirtualKey("VK_F01"))
    lu.assertNil(reserved.mapVirtualKey("VK_INSERT"))
    lu.assertNil(reserved.mapVirtualKey("1"))
end

function TestHotkeys:testDetectionReadsConfigFolderAndHandlesUnmappableAndMissingFiles()
    local h = createHarness()
    local reserved = h.imports["core/hotkeys/reserved.lua"]
    local path = h.nativeConfigRoot .. "/Hell2Modding-Hell2Modding-Hotkeys.cfg"

    os.remove(path)
    lu.assertNil(reserved.detectHell2Modding())

    for raw, binding in pairs({ VK_F1 = "F1", VK_INSERT = false, ["1"] = false }) do
        local file = assert(io.open(path, "w"))
        file:write("gui_toggle = '" .. raw .. "'\n")
        file:close()
        local detected = reserved.detectHell2Modding()
        lu.assertEquals(detected.raw, raw)
        lu.assertEquals(detected.binding, binding or nil)
    end
    os.remove(path)
end

-- -----------------------------------------------------------------------------
-- Declarations
-- -----------------------------------------------------------------------------

local function expectRequestError(h, id, opts, fragment)
    local module = assert(h.public.createModule({ pluginGuid = "decl-mod", id = "Decl", name = "Decl" }))
    local ok, err = pcall(module.hotkeys.request, id, opts)
    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), fragment)
end

function TestHotkeys:testRequestValidatesAtDeclaration()
    local h = createHarness()
    local onPress = function() end
    expectRequestError(h, "bad id", { label = "L", onPress = onPress }, "hotkeys.invalid_declaration")
    expectRequestError(h, "Go", "opts", "opts must be a table")
    expectRequestError(h, "Go", { onPress = onPress }, "label must be a non-empty string")
    expectRequestError(h, "Go", { label = "L" }, "onPress must be a function")
    expectRequestError(h, "Go", { label = "L", onPress = onPress, default = "F13" }, "not a valid binding")
    expectRequestError(h, "Go", { label = "L", onPress = onPress, alias = "bad-alias" }, "alias 'bad-alias'")
    expectRequestError(h, "Go", { label = "L", onPress = onPress, tooltip = 5 }, "tooltip must be a string")
    expectRequestError(h, "Go", { label = "L", onPress = onPress, key = "F5" }, "unknown field 'key'")

    local module = assert(h.public.createModule({ pluginGuid = "decl-mod", id = "Decl", name = "Decl" }))
    module.hotkeys.request("Go", { label = "L", onPress = onPress, alias = "Hotkey" })
    local ok, err = pcall(module.hotkeys.request, "Go", { label = "L", onPress = onPress })
    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "already requested")
    ok, err = pcall(module.hotkeys.request, "Other", { label = "L", onPress = onPress, alias = "Hotkey" })
    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "already used by hotkey 'Go'")

    module.ui.tab(function() end)
    lu.assertTrue(module.activate())
    ok, err = pcall(module.hotkeys.request, "Late", { label = "L", onPress = onPress })
    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "cannot be called after module activation begins")
end

function TestHotkeys:testBindingStorageIsLibDeclaredDataStorage()
    local h = createHarness()
    local _, ok = createModule(h, {
        guid = "storage-mod",
        requests = { request("Go", "Go", "Ctrl+F5", function() end, { alias = "Hotkey" }) },
    })
    lu.assertTrue(ok)
    local liveModule = live(h, "storage-mod")
    local node
    for _, candidate in ipairs(liveModule.getStorage()) do
        if candidate.alias == "Hotkey" then
            node = candidate
        end
    end
    lu.assertEquals(node.type, "string")
    lu.assertEquals(node.default, "Ctrl+F5")
    lu.assertFalse(node._hash)
    lu.assertTrue(node._persist)
    lu.assertEquals(liveModule.read("Hotkey"), "Ctrl+F5")
end

function TestHotkeys:testSavedBindingCarriesOverThroughAlias()
    local h = createHarness()
    createModule(h, {
        guid = "saved-mod",
        config = { Enabled = true, Hotkey = "F11" },
        requests = { request("Go", "Go", "F9", function() end, { alias = "Hotkey" }) },
    })
    lu.assertEquals(status(h, "saved-mod", "Go").binding, "F11")
end

function TestHotkeys:testAliasCollisionWithModuleStorageFailsActivation()
    local h = createHarness()
    local _, ok, err = createModule(h, {
        guid = "collide-mod",
        storage = { { type = "string", alias = "Hotkey", default = "" } },
        requests = { request("Go", "Go", "F9", function() end, { alias = "Hotkey" }) },
    })
    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "hotkeys.alias_collision")
    lu.assertStrContains(tostring(err), "remove it from module.data.define")
    lu.assertNil(live(h, "collide-mod"))
end

-- -----------------------------------------------------------------------------
-- Receipts
-- -----------------------------------------------------------------------------

function TestHotkeys:testHotReloadReplacesGenerationAndRetireLeavesSuccessor()
    local h = createHarness()
    local firstGen, secondGen = counter(), counter()
    createModule(h, { guid = "reload-mod", requests = { request("Go", "Go", "F9", firstGen.onPress) } })
    createModule(h, { guid = "reload-mod", requests = { request("Go", "Go", "F9", secondGen.onPress) } })

    press(h, "F9")
    lu.assertEquals(firstGen.count, 0)
    lu.assertEquals(secondGen.count, 1)
    lu.assertIs(secondGen.host, h.moduleRegistry.getRecord(live(h, "reload-mod")).host)
    lu.assertEquals(status(h, "reload-mod", "Go").state, "active")
end

function TestHotkeys:testFailedActivationRollsBackToPreviousGeneration()
    local h = createHarness()
    local firstGen, secondGen = counter(), counter()
    createModule(h, { guid = "rollback-mod", requests = { request("Go", "Go", "F9", firstGen.onPress) } })
    local _, ok = createModule(h, {
        guid = "rollback-mod",
        requests = { request("Go", "Go", "F9", secondGen.onPress) },
        onActivate = function()
            error("activate boom")
        end,
    })
    lu.assertFalse(ok)

    press(h, "F9")
    lu.assertEquals(firstGen.count, 1)
    lu.assertEquals(secondGen.count, 0)
end

function TestHotkeys:testSuccessorWithoutRequestsRetiresPreviousInstall()
    local h = createHarness()
    local firstGen = counter()
    createModule(h, { guid = "retire-mod", requests = { request("Go", "Go", "F9", firstGen.onPress) } })
    createModule(h, { guid = "retire-mod" })

    press(h, "F9")
    lu.assertEquals(firstGen.count, 0)
    lu.assertNil(status(h, "retire-mod", "Go"))
    lu.assertEquals(#h.hotkeys.listRows(), 0)
end

function TestHotkeys:testReceiptRetireAndRollbackOnlyTouchTheirOwnInstall()
    local h = createHarness()
    local inputs = function(onPress)
        return {
            requests = { { id = "Go", label = "Go", alias = "Hotkey_Go", default = "F9", onPress = onPress, order = 1 } },
            host = {
                isEnabled = function() return true end,
                getMeta = function() return { name = "Manual" } end,
                getModuleId = function() return "Manual" end,
            },
            runtime = {},
            readCommitted = function() return "F9" end,
        }
    end
    local firstGen, secondGen = counter(), counter()
    local first = h.hotkeys.install("manual", inputs(firstGen.onPress))
    local second = h.hotkeys.install("manual", inputs(secondGen.onPress))
    lu.assertNil(h.hotkeys.install("manual", { requests = {} }))

    lu.assertTrue(first.commit())
    lu.assertTrue(second.commit())
    lu.assertTrue(first.retire())
    press(h, "F9")
    lu.assertEquals(secondGen.count, 1)

    lu.assertTrue(second.rollback())
    press(h, "F9")
    lu.assertEquals(firstGen.count, 1)
    lu.assertEquals(secondGen.count, 1)
end

-- -----------------------------------------------------------------------------
-- Tick
-- -----------------------------------------------------------------------------

function TestHotkeys:testTickRegistersOnceAcrossLibReimport()
    local runtimeRoot = {}
    local callbacks = fakeEngine.createCallbacks()
    local first = createHarness({ runtime = runtimeRoot, callbacks = callbacks })
    local calls = counter()
    createModule(first, { guid = "tick-mod", requests = { request("Go", "Go", "F9", calls.onPress) } })
    local anchor = runtimeRoot.registry.hotkeys
    local firstDispatch = anchor.dispatch
    lu.assertEquals(#callbacks.alwaysDraw, 2)

    local second = createHarness({
        runtime = runtimeRoot,
        callbacks = callbacks,
        rom = first.rom,
        nativeConfigRoot = first.nativeConfigRoot,
    })
    lu.assertEquals(#callbacks.alwaysDraw, 2)
    lu.assertNotIs(anchor.dispatch, firstDispatch)
    lu.assertIs(second.hotkeys.status("tick-mod", "Go").state, "active")

    press(first, "F9")
    lu.assertEquals(calls.count, 1)
end

function TestHotkeys:testTickSkipsWhileOverlayIsOpen()
    local h = createHarness()
    local calls = counter()
    createModule(h, { guid = "gui-mod", requests = { request("Go", "Go", "F9", calls.onPress) } })

    h.guiState.open = true
    press(h, "F9")
    lu.assertEquals(calls.count, 0)
    h.guiState.open = false
    press(h, "F9")
    lu.assertEquals(calls.count, 1)
end

function TestHotkeys:testTickMatchesModifiersExactly()
    local h = createHarness()
    local plain, ctrl, ctrlShift = counter(), counter(), counter()
    createModule(h, { guid = "mods-mod", requests = {
        request("Plain", "Plain", "F5", plain.onPress),
        request("Ctrl", "Ctrl", "Ctrl+F5", ctrl.onPress),
        request("CtrlShift", "Ctrl Shift", "Ctrl+Shift+F5", ctrlShift.onPress),
    } })

    press(h, "F5")
    press(h, "F5", { "LeftCtrl" })
    press(h, "F5", { "RightCtrl", "LeftShift" })
    press(h, "F5", { "LeftCtrl", "LeftAlt" })
    press(h, "F5", { "LeftShift" })
    lu.assertEquals(plain.count, 1)
    lu.assertEquals(ctrl.count, 1)
    lu.assertEquals(ctrlShift.count, 1)
end

function TestHotkeys:testTickDispatchesOnlyActiveOwnersOfEnabledModulesOnRuntimeLane()
    local h = createHarness()
    local owner, loser, disabled = counter(), counter(), counter()
    createModule(h, { guid = "a-mod", requests = { request("Go", "Go", "F9", owner.onPress) } })
    createModule(h, { guid = "b-mod", requests = { request("Go", "Go", "F9", loser.onPress) } })
    createModule(h, {
        guid = "c-mod",
        config = { Enabled = false },
        requests = { request("Go", "Go", "F10", disabled.onPress) },
    })

    press(h, "F9")
    press(h, "F10")
    lu.assertEquals(owner.count, 1)
    lu.assertEquals(loser.count, 0)
    lu.assertEquals(disabled.count, 0)
    local record = h.moduleRegistry.getRecord(live(h, "a-mod"))
    lu.assertIs(owner.host, record.host)
    lu.assertIs(owner.runtime, record.runtime)
end

function TestHotkeys:testTickPollsNothingWithoutActiveBindings()
    local h = createHarness()
    createModule(h, { guid = "idle-mod", requests = { request("Go", "Go", nil, function() end) } })
    tick(h)
    tick(h)
    lu.assertEquals(h.imgui.input.pressedCalls, 0)
end

function TestHotkeys:testOnPressErrorIsReportedOncePerBinding()
    local h = createHarness()
    local attempts = 0
    createModule(h, { guid = "err-mod", name = "Err Mod", requests = { request("Go", "Go", "F9", function()
        attempts = attempts + 1
        error("press boom")
    end) } })

    press(h, "F9")
    press(h, "F9")
    lu.assertEquals(attempts, 2)
    lu.assertEquals(#h.warnings, 1)
    lu.assertStrContains(h.warnings[1], "hotkeys.on_press_failed")
    lu.assertStrContains(h.warnings[1], "press boom")

    live(h, "err-mod").writeAndFlush("Hotkey_Go", "F8")
    press(h, "F8")
    press(h, "F8")
    lu.assertEquals(#h.warnings, 2)
end

-- -----------------------------------------------------------------------------
-- UI surfaces
-- -----------------------------------------------------------------------------

function TestHotkeys:testUiAndRuntimeSurfacesReportStatusAndRejectUnknownIds()
    local h = createHarness()
    local captured = {}
    createModule(h, {
        guid = "surface-mod",
        requests = { request("Go", "Go", "F9", function() end) },
        onActivate = function(_, runtime)
            captured.runtime = runtime
        end,
        drawTab = function(_, ui)
            captured.ui = ui
        end,
    })
    live(h, "surface-mod").drawTab()

    lu.assertEquals(captured.runtime.hotkeys.status("Go").state, "active")
    lu.assertIs(captured.ui.hotkeys.status("Go"), captured.runtime.hotkeys.status("Go"))
    for _, call in ipairs({
        function() return captured.runtime.hotkeys.status("Nope") end,
        function() return captured.ui.hotkeys.status("Nope") end,
    }) do
        local ok, err = pcall(call)
        lu.assertFalse(ok)
        lu.assertStrContains(tostring(err), "unknown hotkey 'Nope'")
    end
end

function TestHotkeys:testAuthorSurfaceHasNoHotkeyWidgetOrRefs()
    local h = createHarness()
    local captured = {}
    createModule(h, {
        guid = "surface-mod",
        requests = { request("Go", "Go", "F9", function() end) },
        drawTab = function(_, ui)
            captured.ui = ui
        end,
    })
    live(h, "surface-mod").drawTab()

    lu.assertNil(captured.ui.hotkeys.get)
    lu.assertNil(captured.ui.draw.widgets.hotkey)
    lu.assertNil(h.draw.widgets.hotkey)
end

function TestHotkeys:testStatusTablesAreStableUntilTheirSignatureChanges()
    local h = createHarness()
    createModule(h, { guid = "a-mod", requests = { request("Go", "Go", "F9", function() end) } })
    createModule(h, { guid = "b-mod", requests = { request("Go", "Go", "F10", function() end) } })
    local before = status(h, "a-mod", "Go")
    live(h, "b-mod").writeAndFlush("Hotkey_Go", "F11")
    lu.assertIs(status(h, "a-mod", "Go"), before)
    live(h, "a-mod").writeAndFlush("Hotkey_Go", "F8")
    lu.assertNotIs(status(h, "a-mod", "Go"), before)
end

-- -----------------------------------------------------------------------------
-- Module header block
-- -----------------------------------------------------------------------------

local function headerLabel(ownerId, summary)
    return summary .. "###hotkeys-block-" .. ownerId
end

-- Opens a standalone module's fallback window from its menu item and draws one frame.
local function openFallbackWindow(h, bridge)
    h.imgui.clickMenuItem("Show Mod Menu")
    bridge.addMenuBar()
end

local function drawFallbackWindow(h, bridge)
    h.imgui.resetDrawn()
    bridge.renderWindow()
end

function TestHotkeys:testFallbackHeaderBlockCollapsesToSummaryAndCommitsEdits()
    local h = createHarness()
    local drawOrder = {}
    local _, _, _, bridge = createModule(h, {
        guid = "pause-mod",
        name = "Quick Pause",
        fallbackWindow = true,
        requests = { request("TogglePause", "Pause hotkey", "F9", function() end, { alias = "Hotkey" }) },
        drawTab = function(_, ui)
            drawOrder[#drawOrder + 1] = #h.imgui.drawn.headers
            ui.draw.imgui.Text("module content")
        end,
    })
    local summary = headerLabel("pause-mod", "Hotkeys: Pause hotkey F9")
    openFallbackWindow(h, bridge)

    -- Healthy: one collapsed summary line after the Enabled/Debug row, before module content.
    drawFallbackWindow(h, bridge)
    lu.assertEquals(h.imgui.drawn.checkboxes, { "Enabled", "Debug Mode" })
    lu.assertEquals(h.imgui.drawn.headers, { summary })
    lu.assertEquals(h.imgui.drawn.combos, {})
    lu.assertEquals(drawOrder, { 1 })
    lu.assertEquals(h.imgui.drawn.texts, { "module content" })

    -- Expanding shows the row; editing commits through the module.
    h.imgui.clickHeader(summary)
    drawFallbackWindow(h, bridge)
    lu.assertEquals(h.imgui.comboPreview("##hotkey-key-pause-mod-TogglePause"), "F9")
    lu.assertEquals(h.imgui.drawn.colored, { "F9 - active" })
    h.imgui.clickCombo("##hotkey-modifier-pause-mod-TogglePause", "Ctrl")
    drawFallbackWindow(h, bridge)
    lu.assertEquals(live(h, "pause-mod").read("Hotkey"), "Ctrl+F9")
    lu.assertEquals(h:readNativeConfig("pause-mod"):match("Hotkey = ([^\n]*)"), "\"Ctrl+F9\"")

    -- The open state is remembered; the summary follows the new binding.
    drawFallbackWindow(h, bridge)
    lu.assertEquals(h.imgui.drawn.headers, { headerLabel("pause-mod", "Hotkeys: Pause hotkey Ctrl+F9") })
    lu.assertEquals(h.imgui.drawn.colored, { "Ctrl+F9 - active" })
end

function TestHotkeys:testHeaderBlockSummaryListsEveryRequestAndCachesText()
    local h = createHarness()
    createModule(h, {
        guid = "split-mod",
        requests = {
            request("Prev", "Previous page", "F7", function() end),
            request("Next", "Next page", "", function() end),
        },
    })
    local drawBlock = h.imports["core/hotkeys/module_block.lua"]

    drawBlock(h.rom.ImGui, "split-mod")
    local first = h.imgui.drawn.headers[1]
    lu.assertEquals(first, headerLabel("split-mod", "Hotkeys: Previous page F7, Next page None"))
    h.imgui.resetDrawn()
    drawBlock(h.rom.ImGui, "split-mod")
    lu.assertEquals(h.imgui.drawn.headers[1], first)
    lu.assertIs(h.hotkeys.getOwnerBlock("split-mod"), h.hotkeys.getOwnerBlock("split-mod"))

    -- Modules without requests draw nothing.
    createModule(h, { guid = "plain-mod" })
    h.imgui.resetDrawn()
    lu.assertFalse(drawBlock(h.rom.ImGui, "plain-mod"))
    lu.assertEquals(h.imgui.drawn.headers, {})
end

function TestHotkeys:testHeaderBlockExpandsOnAttentionAndKeepsManualToggleUntilItChanges()
    local h = createHarness({ config = { DebugMode = false, ReservedHotkeys = "" } })
    createModule(h, { guid = "a-mod", name = "A Mod", requests = { request("Go", "Go A", "F9", function() end) } })
    local drawBlock = h.imports["core/hotkeys/module_block.lua"]
    local function draw()
        h.imgui.resetDrawn()
        drawBlock(h.rom.ImGui, "a-mod")
    end

    draw()
    lu.assertEquals(#h.imgui.drawn.combos, 0)

    -- Reserving the key needs attention: the block opens itself.
    h.config.ReservedHotkeys = "F9"
    draw()
    lu.assertEquals(h.imgui.drawn.headers, { headerLabel("a-mod", "Hotkeys: Go A F9 (reserved)") })
    lu.assertEquals(#h.imgui.drawn.combos, 2)
    lu.assertEquals(h.imgui.drawn.colored, { "F9 is reserved (reserved in Lib config)" })

    -- A manual collapse holds while the attention state is unchanged.
    h.imgui.clickHeader(h.imgui.drawn.headers[1])
    draw()
    draw()
    lu.assertEquals(#h.imgui.drawn.combos, 0)

    -- Back to healthy: collapsed again; the disabled state alone does not open it.
    h.config.ReservedHotkeys = ""
    draw()
    lu.assertEquals(#h.imgui.drawn.combos, 0)
    live(h, "a-mod").setEnabled(false)
    draw()
    lu.assertEquals(h.imgui.drawn.headers, { headerLabel("a-mod", "Hotkeys: Go A F9 (disabled)") })
    lu.assertEquals(#h.imgui.drawn.combos, 0)
end

function TestHotkeys:testPackModuleTabDrawsHeaderBlockAfterEnabledRowAndCommitsEdits()
    local h = createHarness()
    local contentDrawn = 0
    createModule(h, {
        guid = "pack-mod",
        requests = { request("Go", "Go", "F9", function() end) },
        drawTab = function()
            contentDrawn = contentDrawn + 1
        end,
    })
    createModule(h, { guid = "rival-mod", requests = { request("Go", "Rival", "F9", function() end) } })
    -- Pack order puts rival-mod first, so pack-mod's request conflicts and its block opens.
    h.hotkeys.setPackOrder("test-pack", 1, { "rival-mod", "pack-mod" })
    lu.assertEquals(status(h, "pack-mod", "Go").state, "conflict")

    local entry = { id = "PackMod", pluginGuid = "pack-mod", _enableLabel = "Enabled##PackMod" }
    local staging = { modules = { PackMod = true } }
    local commits = 0
    local drawModuleTab = h.import("core/modpack/ui/module_tabs.lua", nil, {
        rom = h.rom,
        drawHotkeyBlock = h.imports["core/hotkeys/module_block.lua"],
        staging = staging,
        runtime = {
            commitEntryState = function()
                commits = commits + 1
            end,
        },
        snapshotAccess = {
            getLiveModule = function()
                return live(h, "pack-mod")
            end,
        },
    })

    drawModuleTab(entry, {})
    lu.assertEquals(h.imgui.drawn.checkboxes, { "Enabled##PackMod" })
    lu.assertEquals(h.imgui.drawn.headers, { headerLabel("pack-mod", "Hotkeys: Go F9 (conflict)") })
    lu.assertEquals(h.imgui.drawn.colored, { "F9 is used by rival-mod (Rival); this binding is inactive" })
    lu.assertEquals(contentDrawn, 1)
    lu.assertEquals(commits, 1)

    h.imgui.clickCombo("##hotkey-key-pack-mod-Go", "F4")
    drawModuleTab(entry, {})
    lu.assertEquals(live(h, "pack-mod").read("Hotkey_Go"), "F4")
    lu.assertEquals(status(h, "pack-mod", "Go").state, "active")

    -- A disabled module keeps its block (state disabled) but hides its own content.
    staging.modules.PackMod = false
    live(h, "pack-mod").setEnabled(false)
    h.imgui.resetDrawn()
    drawModuleTab(entry, {})
    lu.assertEquals(h.imgui.drawn.headers, { headerLabel("pack-mod", "Hotkeys: Go F4 (disabled)") })
    lu.assertEquals(contentDrawn, 2)
end

function TestHotkeys:testStandaloneModulesSharingAKeyShowConflictInTheirOwnWindows()
    local h = createHarness()
    local a, b = counter(), counter()
    local _, _, _, bridgeA = createModule(h, {
        guid = "a-mod", name = "A Mod", fallbackWindow = true,
        requests = { request("Go", "Go A", "F9", a.onPress) },
    })
    local _, _, _, bridgeB = createModule(h, {
        guid = "b-mod", name = "B Mod", fallbackWindow = true,
        requests = { request("Go", "Go B", "F9", b.onPress) },
    })
    lu.assertFalse(h.coordinator.hasRegistrations())
    openFallbackWindow(h, bridgeA)
    openFallbackWindow(h, bridgeB)

    -- The owner's window: collapsed, active. The other window: opened on the conflict.
    drawFallbackWindow(h, bridgeA)
    lu.assertEquals(h.imgui.drawn.headers, { headerLabel("a-mod", "Hotkeys: Go A F9") })
    lu.assertEquals(h.imgui.drawn.colored, {})
    drawFallbackWindow(h, bridgeB)
    lu.assertEquals(h.imgui.drawn.headers, { headerLabel("b-mod", "Hotkeys: Go B F9 (conflict)") })
    lu.assertEquals(h.imgui.drawn.colored, { "F9 is used by A Mod (Go A); this binding is inactive" })

    press(h, "F9")
    lu.assertEquals(a.count, 1)
    lu.assertEquals(b.count, 0)

    -- Rebinding in B's own window resolves the conflict.
    h.imgui.clickCombo("##hotkey-key-b-mod-Go", "F10")
    drawFallbackWindow(h, bridgeB)
    lu.assertEquals(live(h, "b-mod").read("Hotkey_Go"), "F10")
    press(h, "F10")
    lu.assertEquals(b.count, 1)
end

-- -----------------------------------------------------------------------------
-- Overview page
-- -----------------------------------------------------------------------------

local OVERVIEW_COLORS = { info = { 1, 1, 1, 1 }, text = { 1, 1, 1, 1 } }

local function createOverview(h)
    local drawOverview = h.imports["core/hotkeys/overview.lua"]
    return function()
        drawOverview(h.rom.ImGui, OVERVIEW_COLORS)
    end
end

function TestHotkeys:testOverviewListsConflictsFirstAndEditsCommitThroughOwningModule()
    local h = createHarness()
    createModule(h, { guid = "a-mod", name = "A Mod", requests = { request("Go", "Go A", "F9", function() end) } })
    createModule(h, { guid = "b-mod", name = "B Mod", requests = { request("Go", "Go B", "F9", function() end) } })
    createModule(h, { guid = "c-mod", name = "C Mod", requests = { request("Go", "Go C", "F3", function() end) } })
    local drawOverview = createOverview(h)

    drawOverview()
    local headers = {}
    for _, text in ipairs(h.imgui.drawn.colored) do
        if string.find(text, " - Go ", 1, true) then
            headers[#headers + 1] = text
        end
    end
    lu.assertEquals(headers, { "B Mod - Go B", "A Mod - Go A", "C Mod - Go C" })

    -- Rebinding the conflicting request from the overview commits through b-mod.
    h.imgui.resetDrawn()
    h.imgui.clickCombo("##hotkey-key-b-mod-Go", "F4")
    drawOverview()
    lu.assertEquals(live(h, "b-mod").read("Hotkey_Go"), "F4")
    lu.assertEquals(h:readNativeConfig("b-mod"):match("Hotkey_Go = ([^\n]*)"), "\"F4\"")
    lu.assertEquals(status(h, "b-mod", "Go").state, "active")
end

function TestHotkeys:testOverviewEditsManualReservedList()
    local h = createHarness({ config = { DebugMode = false, ReservedHotkeys = "F7" } })
    local drawOverview = createOverview(h)

    drawOverview()
    lu.assertTrue(table.concat(h.imgui.drawn.texts, "|"):find("Hell2Modding overlay key: not detected", 1, true) ~= nil)

    -- Pick Shift+F2 in the add picker, then press Add.
    local pickerKeyCombo, pickerModifierCombo
    for _, combo in ipairs(h.imgui.drawn.combos) do
        if string.find(combo.id, "##hotkey-key-picker-", 1, true) then
            pickerKeyCombo = combo.id
        elseif string.find(combo.id, "##hotkey-modifier-picker-", 1, true) then
            pickerModifierCombo = combo.id
        end
    end
    h.imgui.clickCombo(pickerModifierCombo, "Shift")
    drawOverview()
    h.imgui.clickCombo(pickerKeyCombo, "F2")
    drawOverview()
    h.imgui.clickButton("Add##hotkeys-reserved-add")
    drawOverview()
    lu.assertEquals(h.config.ReservedHotkeys, "F7,Shift+F2")

    h.imgui.clickButton("Remove##hotkeys-reserved-1")
    drawOverview()
    lu.assertEquals(h.config.ReservedHotkeys, "Shift+F2")
end

function TestHotkeys:testFallbackHotkeysWindowDrawsOverviewAndRegistersOnceAcrossLibReimport()
    local runtimeRoot = {}
    local callbacks = fakeEngine.createCallbacks()
    local h = createHarness({ runtime = runtimeRoot, callbacks = callbacks })
    createModule(h, { guid = "a-mod", name = "A Mod", requests = { request("Go", "Go A", "F9", function() end) } })
    lu.assertEquals(#callbacks.imgui, 1)
    local function render()
        h.imgui.resetDrawn()
        callbacks.imgui[1]()
    end

    render()
    lu.assertEquals(h.imgui.drawn.windows, {})

    h.core.hotkeysWindow.toggle()
    render()
    lu.assertEquals(h.imgui.drawn.windows, { "Hotkeys###adamant-lib-hotkeys" })
    lu.assertEquals(h.imgui.drawn.colored[1], "Hotkeys requested by every loaded module. Conflicts are listed first.")
    lu.assertEquals(h.imgui.comboPreview("##hotkey-key-a-mod-Go"), "F9")

    -- A re-import swaps the renderer without registering a second window.
    local second = createHarness({
        runtime = runtimeRoot,
        callbacks = callbacks,
        rom = h.rom,
        nativeConfigRoot = h.nativeConfigRoot,
    })
    lu.assertEquals(#callbacks.imgui, 1)
    render()
    lu.assertEquals(h.imgui.drawn.windows, {})
    second.core.hotkeysWindow.toggle()
    render()
    lu.assertEquals(h.imgui.drawn.windows, { "Hotkeys###adamant-lib-hotkeys" })

    -- A registered coordinator owns the overview; the Lib window stays hidden.
    second.coordinator.register("some-pack", "Some Pack", { ModEnabled = true })
    render()
    lu.assertEquals(h.imgui.drawn.windows, {})
end

function TestHotkeys:testBareReservedKeyCoversEveryModifierCombination()
    local bindings = dofile("src/core/hotkeys/bindings.lua")
    local reserved = assert(loadfile("src/core/hotkeys/reserved.lua"))({ rom = {}, bindings = bindings })
    local map = reserved.buildMap({ binding = "F1" }, { "F2", "Ctrl+F3" })
    lu.assertEquals(map["F1"], reserved.HELL2MODDING_REASON)
    lu.assertEquals(map["Ctrl+F1"], reserved.HELL2MODDING_REASON)
    lu.assertEquals(map["Ctrl+Shift+Alt+F1"], reserved.HELL2MODDING_REASON)
    lu.assertEquals(map["Shift+F2"], reserved.MANUAL_REASON)
    lu.assertEquals(map["Ctrl+F3"], reserved.MANUAL_REASON)
    lu.assertNil(map["F3"])
    lu.assertNil(map["Shift+F3"])
end
