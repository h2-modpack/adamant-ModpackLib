local WidgetFns = public.widgets

local function ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and type(imgui.IsItemHovered) == "function" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
end

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

function WidgetFns.confirmButton(imgui, id, label, opts)
    opts = opts or {}
    local popupId = tostring(id) .. "##popup"
    local changed = false
    if imgui.Button(tostring(label or "") .. "##" .. tostring(id)) and type(imgui.OpenPopup) == "function" then
        imgui.OpenPopup(popupId)
    end
    ShowTooltip(imgui, opts.tooltip)
    if type(imgui.BeginPopup) == "function" and imgui.BeginPopup(popupId) then
        local confirmLabel = tostring(opts.confirmLabel or "Confirm")
        local cancelLabel = tostring(opts.cancelLabel or "Cancel")
        if imgui.Button(confirmLabel .. "##confirm_" .. tostring(id)) then
            if type(opts.onConfirm) == "function" then
                opts.onConfirm(imgui)
            end
            if type(imgui.CloseCurrentPopup) == "function" then
                imgui.CloseCurrentPopup()
            end
            changed = true
        end
        if type(imgui.SameLine) == "function" then
            imgui.SameLine()
        end
        if imgui.Button(cancelLabel .. "##cancel_" .. tostring(id)) and type(imgui.CloseCurrentPopup) == "function" then
            imgui.CloseCurrentPopup()
        end
        if type(imgui.EndPopup) == "function" then
            imgui.EndPopup()
        end
    end
    return changed
end
