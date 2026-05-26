local deps = ...

local widgets = deps.widgets
local nav = deps.nav
local logging = deps.logging
local storage = deps.storage
local imgui = deps.rom.ImGui
local phaseGate = deps.phaseGate

local uiDraw = {}
local draw = {
    imgui = imgui,
    widgets = {},
    nav = {},
}

---@class DrawWidgets
---@field separator fun()
---@field text fun(text: any, opts: TextOpts|nil)
---@field button fun(label: any, opts: ButtonOpts|nil): boolean
---@field confirmButton fun(id: string|number, label: any, opts: ConfirmButtonOpts|nil): boolean
---@field inputText fun(target: StorageField, opts: InputTextOpts|nil): boolean
---@field dropdown fun(target: StorageField, opts: DropdownOpts|nil): boolean
---@field packedDropdown fun(target: StorageField, opts: PackedDropdownOpts|nil): boolean
---@field getPackedChoiceAlias fun(target: StorageField, opts: PackedDropdownOpts|PackedRadioOpts|nil): string|nil
---@field radio fun(target: StorageField, opts: RadioOpts|nil): boolean
---@field packedRadio fun(target: StorageField, opts: PackedRadioOpts|nil): boolean
---@field stepper fun(target: StorageField, opts: StepperOpts|nil): boolean
---@field steppedRange fun(minTarget: StorageField, maxTarget: StorageField, opts: SteppedRangeOpts|nil): boolean
---@field checkbox fun(target: StorageField, opts: CheckboxOpts|nil): boolean
---@field packedCheckboxList fun(target: StorageField, opts: PackedCheckboxListOpts|nil): boolean

---@class DrawNav
---@field verticalTabs fun(opts: VerticalTabsOpts|nil): string|number|nil

local function getActiveDrawLogContext()
    local context = phaseGate.getActiveDrawContext()
    if type(context) ~= "table" or type(context.logPrefix) ~= "string" then
        logging.violate("phase.invalid_ui_access", "draw logging can only run during a module draw callback")
    end
    return context
end

function draw.log(fmt, ...)
    local context = getActiveDrawLogContext()
    return logging.printWithPrefix(context.logPrefix, fmt, ...)
end

function draw.logIf(fmt, ...)
    local context = getActiveDrawLogContext()
    return logging.printWithPrefixIf(context.debugEnabled == true, context.logPrefix, fmt, ...)
end

local function resolveField(target, methodName)
    if storage.field.is(target) then
        return target
    end
    logging.violate("widgets.invalid_field_target",
        "draw.widgets.%s: expected StorageField",
        tostring(methodName)
    )
end

local function callTwoFieldWidget(methodName, firstTarget, secondTarget, opts)
    phaseGate.requireAnyDraw()
    local firstField = resolveField(firstTarget, methodName)
    local secondField = resolveField(secondTarget, methodName)
    return widgets[methodName](draw.imgui, firstField, secondField, opts)
end

local function callFieldWidget(methodName, target, opts)
    phaseGate.requireAnyDraw()
    local field = resolveField(target, methodName)
    return widgets[methodName](draw.imgui, field, opts)
end

function draw.widgets.separator()
    phaseGate.requireAnyDraw()
    return widgets.separator(draw.imgui)
end

function draw.widgets.text(text, opts)
    phaseGate.requireAnyDraw()
    return widgets.text(draw.imgui, text, opts)
end

function draw.widgets.button(label, opts)
    phaseGate.requireAnyDraw()
    return widgets.button(draw.imgui, label, opts)
end

function draw.widgets.confirmButton(id, label, opts)
    phaseGate.requireAnyDraw()
    return widgets.confirmButton(draw.imgui, id, label, opts)
end

function draw.widgets.inputText(target, opts)
    return callFieldWidget("inputText", target, opts)
end

function draw.widgets.dropdown(target, opts)
    return callFieldWidget("dropdown", target, opts)
end

function draw.widgets.packedDropdown(target, opts)
    return callFieldWidget("packedDropdown", target, opts)
end

function draw.widgets.getPackedChoiceAlias(target, opts)
    phaseGate.requireAnyDraw()
    local field = resolveField(target, "getPackedChoiceAlias")
    return widgets.getPackedChoiceAlias(field, opts)
end

function draw.widgets.radio(target, opts)
    return callFieldWidget("radio", target, opts)
end

function draw.widgets.packedRadio(target, opts)
    return callFieldWidget("packedRadio", target, opts)
end

function draw.widgets.stepper(target, opts)
    return callFieldWidget("stepper", target, opts)
end

function draw.widgets.steppedRange(minTarget, maxTarget, opts)
    return callTwoFieldWidget("steppedRange", minTarget, maxTarget, opts)
end

function draw.widgets.checkbox(target, opts)
    return callFieldWidget("checkbox", target, opts)
end

function draw.widgets.packedCheckboxList(target, opts)
    return callFieldWidget("packedCheckboxList", target, opts)
end

function draw.nav.verticalTabs(opts)
    phaseGate.requireAnyDraw()
    return nav.verticalTabs(draw.imgui, opts)
end

---@return DrawContext
function uiDraw.get()
    return draw
end

return uiDraw
