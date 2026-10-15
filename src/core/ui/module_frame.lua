-- Shared module frame, drawn by the modpack window's module page and the standalone fallback
-- window so the two cannot drift:
--
--   [x] Enabled
--   (header, when the module declares `ui.header`)
--   [ Module | Hotkeys & Advanced ]               -- `ui.tab`
--   [ <tab> | <tab> | ... | Hotkeys & Advanced ]  -- `ui.tabs`, in declaration order
--
-- - Enabled sits above everything and is always visible. A disabled module draws only Enabled.
-- - Module tabs draw the module's own content: "Module" for `ui.tab`, one tab per `ui.tabs` entry.
--   A tab's optional `state` colours its label ("attention" / "muted"); "###" ids keep the selected
--   tab across label and colour changes.
-- - Header and the active module tab share one commit per frame through the mode's `commit` path.
-- - Hotkeys & Advanced is Lib-owned and always last: Debug Mode and Resync for this module, then the
--   module's hotkey rows. Modules without hotkeys label it "Advanced". It reads "... (!)" while any of the
--   module's hotkeys is conflict, reserved or invalid.
--
-- Each mode supplies its own enable, debug, resync, module and commit paths through `ops`; the frame
-- owns layout only. Labels are built once per module layout, so drawing allocates nothing.

local deps = ...

local hotkeys = deps.hotkeys
local drawHotkeyBlock = deps.drawHotkeyBlock
local statusColors = deps.statusColors
local TEXT_COLOR_ID = deps.imguiCol.Text

local TAB_STATE_COLORS = {
    attention = statusColors.attention,
    muted = statusColors.muted,
}

---@class AdamantModpackLib.ModuleFrameOps
---@field isEnabled fun(): boolean Enabled state the checkbox shows.
---@field setEnabled fun(enabled: boolean) Mode-specific enable path.
---@field enabledTooltip string? Hover text for the Enabled checkbox.
---@field getModule fun(): AdamantModpackLib.ManagedModule? Live module whose header and tabs the frame draws.
---@field commit fun() Commits the frame's staged writes; called once after the header and active tab drew.
---@field isDebugMode fun(): boolean
---@field setDebugMode fun(enabled: boolean) Writes through the module's `setDebugMode`.
---@field resync fun() Resyncs this module only.

---@class AdamantModpackLib.ModuleFrame
---@field draw fun(imgui: table)

---@param ownerId string
---@param ops AdamantModpackLib.ModuleFrameOps
---@return AdamantModpackLib.ModuleFrame
return function(ownerId, ops)
    local tabBarId = "##module-frame-" .. ownerId
    local moduleLabel = "Module###module-" .. ownerId
    local advancedId = "###advanced-" .. ownerId
    local advancedLabel = "Advanced" .. advancedId
    local hotkeysAdvancedLabel = "Hotkeys & Advanced" .. advancedId
    local hotkeysAdvancedAttentionLabel = "Hotkeys & Advanced (!)" .. advancedId
    local tooltip = ops.enabledTooltip
    if tooltip == "" then
        tooltip = nil
    end

    -- Module tab labels for the layout last drawn; rebuilt only when the live module's layout
    -- changes (a reloaded module). Without a layout the frame shows the single Module tab.
    local builtLayout = nil
    local tabLabels = { moduleLabel }
    local tabHasState = { false }
    local tabCount = 1

    ---@param layout AdamantModpackLib.ModuleUiLayout?
    local function buildTabLabels(layout)
        builtLayout = layout
        if layout == nil or layout.tabs == nil then
            tabLabels = { moduleLabel }
            tabHasState = { false }
            tabCount = 1
            return
        end
        tabLabels = {}
        tabHasState = {}
        for index, tab in ipairs(layout.tabs) do
            tabLabels[index] = tab.label .. "###tab-" .. ownerId .. "-" .. tab.id
            tabHasState[index] = tab.hasState
        end
        tabCount = #layout.tabs
    end

    local function drawSettings(imgui)
        imgui.Spacing()
        local debugValue, debugChanged = imgui.Checkbox("Debug Mode", ops.isDebugMode())
        if debugChanged then
            ops.setDebugMode(debugValue)
        end
        imgui.SameLine()
        if imgui.Button("Resync State") then
            ops.resync()
        end
        drawHotkeyBlock(imgui, ownerId)
    end

    ---@param module AdamantModpackLib.ManagedModule?
    ---@return boolean drewModule
    local function drawModuleTabs(imgui, module)
        local drewModule = false
        for index = 1, tabCount do
            local color = nil
            if module ~= nil and tabHasState[index] then
                color = TAB_STATE_COLORS[module.readTabState(index)]
            end
            if color ~= nil then
                imgui.PushStyleColor(TEXT_COLOR_ID, color[1], color[2], color[3], color[4])
            end
            local open = imgui.BeginTabItem(tabLabels[index])
            if color ~= nil then
                imgui.PopStyleColor()
            end
            if open then
                imgui.Spacing()
                if module ~= nil then
                    module.drawTab(index)
                    drewModule = true
                end
                imgui.EndTabItem()
            end
        end
        return drewModule
    end

    local frame = {}

    function frame.draw(imgui)
        local enabledValue, enabledChanged = imgui.Checkbox("Enabled", ops.isEnabled())
        if enabledChanged then
            ops.setEnabled(enabledValue)
        end
        if tooltip ~= nil and imgui.IsItemHovered() then
            imgui.SetTooltip(tooltip)
        end
        -- A disabled module is just its switch; its hotkeys stay editable in Lib's Hotkeys window.
        if not ops.isEnabled() then
            return
        end

        local module = ops.getModule()
        local layout = module ~= nil and module.getUiLayout() or nil
        if layout ~= builtLayout then
            buildTabLabels(layout)
        end
        local drewModule = false
        if layout ~= nil and layout.hasHeader then
            module.drawHeader()
            drewModule = true
        end

        if imgui.BeginTabBar(tabBarId) then
            if drawModuleTabs(imgui, module) then
                drewModule = true
            end
            local block = hotkeys.getOwnerBlock(ownerId)
            local label = advancedLabel
            if block ~= nil then
                label = block.attention and hotkeysAdvancedAttentionLabel or hotkeysAdvancedLabel
            end
            if imgui.BeginTabItem(label) then
                drawSettings(imgui)
                imgui.EndTabItem()
            end
            imgui.EndTabBar()
        end

        -- One commit covers the header and the active module tab.
        if drewModule then
            ops.commit()
        end
    end

    return frame
end
