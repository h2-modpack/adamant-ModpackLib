local helpers = ...
local widgets = {}

function widgets.button(imgui, label, opts)
    opts = opts or helpers.EMPTY_OPTS
    local id = tostring(opts.id or label or "")
    local clicked = imgui.Button(tostring(label or "") .. "##" .. id)
    helpers.ShowTooltip(imgui, opts.tooltip)
    if clicked then
        helpers.StageAction("draw.widgets.button", opts, true)
    end
    return clicked == true
end

function widgets.confirmButton(imgui, id, label, opts)
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

return widgets
