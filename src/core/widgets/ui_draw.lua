local deps = ...

local widgets = deps.widgets
local nav = deps.nav
local logging = deps.logging
local storage = deps.storage
local controlsDraw = deps.controlsDraw

-- One draw surface shared by every module's `ui.draw`.
---@type AdamantModpackLib.DrawContext
local draw = {
    imgui = deps.rom.ImGui,
    widgets = {},
    nav = {},
}

-- How many StorageField targets each `draw.widgets.<name>` takes before its opts. Arity 0
-- widgets take their author arguments as-is after `imgui`.
local WIDGET_FIELD_ARITY = {
    separator = 0,
    text = 0,
    button = 0,
    confirmButton = 0,
    inputText = 1,
    dropdown = 1,
    packedDropdown = 1,
    radio = 1,
    packedRadio = 1,
    stepper = 1,
    checkbox = 1,
    packedCheckboxList = 1,
    steppedRange = 2,
}

local function resolveField(target, methodName)
    if storage.field.is(target) then
        return target
    end
    logging.violate("widgets.invalid_field_target",
        "draw.widgets.%s: expected StorageField",
        tostring(methodName)
    )
end

local function bindWidget(methodName, widget, arity)
    if arity == 0 then
        return function(a, b, c)
            return widget(draw.imgui, a, b, c)
        end
    elseif arity == 1 then
        return function(target, opts)
            return widget(draw.imgui, resolveField(target, methodName), opts)
        end
    end
    return function(firstTarget, secondTarget, opts)
        return widget(draw.imgui, resolveField(firstTarget, methodName), resolveField(secondTarget, methodName), opts)
    end
end

for methodName, arity in pairs(WIDGET_FIELD_ARITY) do
    draw.widgets[methodName] = bindWidget(methodName, widgets[methodName], arity)
end

function draw.widgets.getPackedChoiceAlias(target, opts)
    return widgets.getPackedChoiceAlias(resolveField(target, "getPackedChoiceAlias"), opts)
end

function draw.nav.verticalTabs(opts)
    return nav.verticalTabs(draw.imgui, opts)
end

function draw.control(control, viewName, ...)
    return controlsDraw.render(draw, control, viewName, ...)
end

return draw
