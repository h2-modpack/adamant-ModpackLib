local WidgetFns = public.widgets

---@class ButtonOpts
---@field id string|number|nil
---@field tooltip string|nil
---@field onClick fun(imgui: table)|nil

---@class ConfirmButtonOpts
---@field tooltip string|nil
---@field confirmLabel string|nil
---@field cancelLabel string|nil
---@field onConfirm fun(imgui: table)|nil

local function ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
end

---@param imgui table
---@param label any
---@param opts ButtonOpts|nil
---@return boolean
function WidgetFns.button(imgui, label, opts)
    opts = opts or {}
    local id = tostring(opts.id or label or "")
    local clicked = imgui.Button(tostring(label or "") .. "##" .. id)
    ShowTooltip(imgui, opts.tooltip)
    if clicked and type(opts.onClick) == "function" then
        opts.onClick(imgui)
    end
    return clicked == true
end

---@param imgui table
---@param id string|number
---@param label any
---@param opts ConfirmButtonOpts|nil
---@return boolean
function WidgetFns.confirmButton(imgui, id, label, opts)
    opts = opts or {}
    local popupId = tostring(id) .. "##popup"
    local changed = false
    if imgui.Button(tostring(label or "") .. "##" .. tostring(id)) then
        imgui.OpenPopup(popupId)
    end
    ShowTooltip(imgui, opts.tooltip)
    if imgui.BeginPopup(popupId) then
        local confirmLabel = tostring(opts.confirmLabel or "Confirm")
        local cancelLabel = tostring(opts.cancelLabel or "Cancel")
        if imgui.Button(confirmLabel .. "##confirm_" .. tostring(id)) then
            if type(opts.onConfirm) == "function" then
                opts.onConfirm(imgui)
            end
            imgui.CloseCurrentPopup()
            changed = true
        end
        imgui.SameLine()
        if imgui.Button(cancelLabel .. "##cancel_" .. tostring(id)) then
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end
    return changed
end
