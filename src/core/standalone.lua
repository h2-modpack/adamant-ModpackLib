local internal = AdamantModpackLib_Internal
local libWarn = internal.logging.warn
local coordinator = public.coordinator

--- Creates a standalone menu renderer for a regular coordinated-capable module.
---@param def table Module definition declaring UI, storage, and mutation behavior.
---@param store table Managed module store associated with the definition.
---@return function render Menu render callback that draws the standalone module UI.
function coordinator.standaloneUI(def, store)
    local function TrySetEnabled(enabled)
        local ok, err = public.mutation.setEnabled(def, store, enabled)
        if ok then
            if public.mutation.mutatesRunData(def) then rom.game.SetupRunData() end
        else
            libWarn("%s %s failed: %s",
                tostring(def.name or def.id or "module"),
                enabled and "enable" or "disable",
                tostring(err))
        end
        return ok, err
    end

    return function()
        if def.modpack and internal.coordinators[def.modpack] then return end
        if rom.ImGui.BeginMenu(def.name) then
            local imgui = rom.ImGui
            local enabled = store.read("Enabled") == true
            local val, chg = imgui.Checkbox(def.name, enabled)
            if chg then
                TrySetEnabled(val)
            end
            if imgui.IsItemHovered() and (def.tooltip or "") ~= "" then
                imgui.SetTooltip(def.tooltip)
            end

            local dbgVal, dbgChg = imgui.Checkbox("Debug Mode", store.read("DebugMode") == true)
            if dbgChg then
                store.write("DebugMode", dbgVal)
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip("Print diagnostic warnings to the console for this module.")
            end

            if store.uiState and imgui.Button("Audit + Resync UI State") then
                public.special.auditAndResyncState(def.name or def.id or "module", store.uiState)
            end

            imgui.EndMenu()
        end
    end
end
