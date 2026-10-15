-- Lib's settings window ("adamant-lib"), opened from the `adamant-lib` menu, from each module's
-- Hotkeys & Advanced tab, and from a pack's Settings page. Tabs:
-- - Hotkeys: every module's hotkeys across every pack and standalone module (conflicts first), plus
--   the reserved keys. This is the only reserved-key editor.
-- - Debug: Lib Policy Debug and the Lib diagnostics toggles.

local deps = ...

local rom = deps.rom
local createTheme = deps.createTheme
local drawHotkeys = deps.drawHotkeys
local libConfig = deps.libConfig
local uiRegistry = deps.uiRegistry

local DEFAULT_WINDOW_WIDTH = 720
local DEFAULT_WINDOW_HEIGHT = 560
local WINDOW_TITLE = "adamant-lib###adamant-lib"
local TAB_BAR_ID = "##adamant-lib-tabs"

local libWindow = {}
local showWindow = false
-- Set by openHotkeys: select the Hotkeys tab on the next draw.
local selectHotkeys = false
local theme = nil
-- Diagnostics keys are fixed by Lib config; sorted once on first draw.
local diagnosticKeys = nil

function libWindow.open()
    showWindow = true
end

--- Opens the window on its Hotkeys tab (the module and pack "All hotkeys..." buttons).
function libWindow.openHotkeys()
    showWindow = true
    selectHotkeys = true
end

local function sortedDiagnosticKeys()
    if diagnosticKeys == nil then
        diagnosticKeys = {}
        for key, diagnostic in pairs(libConfig.Diagnostics) do
            if type(diagnostic) == "table" then
                diagnosticKeys[#diagnosticKeys + 1] = key
            end
        end
        table.sort(diagnosticKeys)
    end
    return diagnosticKeys
end

local function drawDebug(imgui)
    local libVal, libChg = imgui.Checkbox("Lib Policy Debug", libConfig.DebugMode == true)
    if libChg then
        libConfig.DebugMode = libVal
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Print lib debug-policy warnings. Shared across all packs.")
    end

    local diagnostics = libConfig.Diagnostics
    for _, key in ipairs(sortedDiagnosticKeys()) do
        local diagnostic = diagnostics[key]
        local diagVal, diagChg = imgui.Checkbox(diagnostic.label, diagnostic.enabled == true)
        if diagChg then
            diagnostic.enabled = diagVal
        end
    end
end

local function drawContents(imgui)
    if not imgui.BeginTabBar(TAB_BAR_ID) then
        return
    end
    -- BeginTabItem(label, flags) selects without the close button the `open` overload adds.
    local tabFlags = rom.ImGuiTabItemFlags
    local hotkeysOpen
    if selectHotkeys and tabFlags ~= nil and tabFlags.SetSelected ~= nil then
        hotkeysOpen = imgui.BeginTabItem("Hotkeys", tabFlags.SetSelected)
    else
        hotkeysOpen = imgui.BeginTabItem("Hotkeys")
    end
    selectHotkeys = false
    if hotkeysOpen then
        drawHotkeys(imgui, theme.colors)
        imgui.EndTabItem()
    end
    if imgui.BeginTabItem("Debug") then
        drawDebug(imgui)
        imgui.EndTabItem()
    end
    imgui.EndTabBar()
end

local function render()
    if not showWindow then
        return
    end
    local imgui = rom.ImGui
    -- Created lazily because it reads rom.ImGui / rom.ImGuiCol, which may not exist at import.
    theme = theme or createTheme()

    local beganWindow = false
    local openState = showWindow
    theme.PushTheme()
    local ok, err = xpcall(function()
        imgui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
        local shouldDraw
        openState, shouldDraw = imgui.Begin(WINDOW_TITLE, showWindow)
        beganWindow = true
        if shouldDraw then
            drawContents(imgui)
        end
    end, debug.traceback)
    if beganWindow then
        imgui.End()
    end
    theme.PopTheme()

    if not ok then
        error(err)
    end
    if openState == false then
        showWindow = false
    end
end

-- Registered once per process; the callback late-reads the anchor so a Lib re-import swaps the
-- renderer without registering a second window.
uiRegistry.renderLibWindow = render
if not uiRegistry.libWindowRegistered
    and type(rom.gui) == "table" and type(rom.gui.add_imgui) == "function" then
    rom.gui.add_imgui(function()
        local renderWindow = uiRegistry.renderLibWindow
        if renderWindow ~= nil then
            renderWindow()
        end
    end)
    uiRegistry.libWindowRegistered = true
end

return libWindow
