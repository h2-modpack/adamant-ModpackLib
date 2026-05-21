local helpers = ...

---@class ButtonOpts
---@field id string|number|nil
---@field tooltip string|nil
---@field action DrawActionRef|nil Staged action ref to replace when clicked.
---@field value any Staged action payload.
---@field onClick fun(imgui: table)|nil

---@class ConfirmButtonOpts
---@field tooltip string|nil
---@field confirmLabel string|nil
---@field cancelLabel string|nil
---@field action DrawActionRef|nil Staged action ref to replace when confirmed.
---@field value any Staged action payload.
---@field onConfirm fun(imgui: table)|nil

---@param imgui table
---@param label any
---@param opts ButtonOpts|nil
---@return boolean
function helpers.widgets.button(imgui, label, opts)
    opts = opts or helpers.EMPTY_OPTS
    local id = tostring(opts.id or label or "")
    local clicked = imgui.Button(tostring(label or "") .. "##" .. id)
    helpers.ShowTooltip(imgui, opts.tooltip)
    if clicked then
        if type(opts.onClick) == "function" then
            opts.onClick(imgui)
        end
        helpers.StageAction("draw.widgets.button", opts, true)
    end
    return clicked == true
end

---@param imgui table
---@param id string|number
---@param label any
---@param opts ConfirmButtonOpts|nil
---@return boolean
function helpers.widgets.confirmButton(imgui, id, label, opts)
    opts = opts or helpers.EMPTY_OPTS
    local popupId = tostring(id) .. "##popup"
    local changed = false
    if imgui.Button(tostring(label or "") .. "##" .. tostring(id)) then
        imgui.OpenPopup(popupId)
    end
    helpers.ShowTooltip(imgui, opts.tooltip)
    if imgui.BeginPopup(popupId) then
        local confirmLabel = tostring(opts.confirmLabel or "Confirm")
        local cancelLabel = tostring(opts.cancelLabel or "Cancel")
        if imgui.Button(confirmLabel .. "##confirm_" .. tostring(id)) then
            if type(opts.onConfirm) == "function" then
                opts.onConfirm(imgui)
            end
            helpers.StageAction("draw.widgets.confirmButton", opts, true)
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
