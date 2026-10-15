-- Lib's own Hotkeys window for fallback mode (no coordinator registered). The `adamant-lib` menu
-- toggles it; it draws the same Hotkeys overview the modpack window shows as its Hotkeys tab.

local deps = ...

local rom = deps.rom
local coordination = deps.coordination
local createTheme = deps.createTheme
local drawOverview = deps.drawOverview
local fallbackRegistry = deps.fallbackRegistry

local DEFAULT_WINDOW_WIDTH = 720
local DEFAULT_WINDOW_HEIGHT = 560
local WINDOW_TITLE = "Hotkeys###adamant-lib-hotkeys"

local hotkeysWindow = {}
local showWindow = false
local theme = nil

function hotkeysWindow.toggle()
    showWindow = not showWindow
end

---@return boolean
function hotkeysWindow.isOpen()
    return showWindow
end

local function render()
    -- A registered coordinator hides the `adamant-lib` menu; its modpack window owns the overview.
    if not showWindow or coordination.hasRegistrations() then
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
            drawOverview(imgui, theme.colors)
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
fallbackRegistry.renderHotkeysWindow = render
if not fallbackRegistry.hotkeysWindowRegistered
    and type(rom.gui) == "table" and type(rom.gui.add_imgui) == "function" then
    rom.gui.add_imgui(function()
        local renderWindow = fallbackRegistry.renderHotkeysWindow
        if renderWindow ~= nil then
            renderWindow()
        end
    end)
    fallbackRegistry.hotkeysWindowRegistered = true
end

return hotkeysWindow
