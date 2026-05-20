local helpers = ...

---@class ButtonOpts
---@field id string|number|nil
---@field tooltip string|nil
---@field action string|DrawActionRef|nil Staged action ref, or legacy session action key, to replace when clicked.
---@field value any Staged session action payload.
---@field onClick fun(imgui: table)|nil

---@class ConfirmButtonOpts
---@field tooltip string|nil
---@field confirmLabel string|nil
---@field cancelLabel string|nil
---@field action string|DrawActionRef|nil Staged action ref, or legacy session action key, to replace when confirmed.
---@field value any Staged session action payload.
---@field onConfirm fun(imgui: table)|nil

local function StageAction(session, opts)
    local action = opts.action
    if action == nil then
        return
    end
    if helpers.actions.isDrawActionRef(action) then
        action:stage(opts.value)
        return
    end
    if type(action) == "string" then
        session.stageAction(action, opts.value)
        return
    end
    helpers.logging.violate(
        "widgets.invalid_action",
        "draw.widgets.button: opts.action must be a draw action ref or legacy action key string"
    )
end

---@param imgui table
---@param session Session
---@param label any
---@param opts ButtonOpts|nil
---@return boolean
function helpers.widgets.button(imgui, session, label, opts)
    opts = opts or {}
    local id = tostring(opts.id or label or "")
    local clicked = imgui.Button(tostring(label or "") .. "##" .. id)
    helpers.ShowTooltip(imgui, opts.tooltip)
    if clicked then
        if type(opts.onClick) == "function" then
            opts.onClick(imgui)
        end
        StageAction(session, opts)
    end
    return clicked == true
end

---@param imgui table
---@param session Session
---@param id string|number
---@param label any
---@param opts ConfirmButtonOpts|nil
---@return boolean
function helpers.widgets.confirmButton(imgui, session, id, label, opts)
    opts = opts or {}
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
            StageAction(session, opts)
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
