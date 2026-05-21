local deps = ...

local widgets = {}
local imguiHelpers = import 'core/widgets/imgui_helpers.lua'
local widgetHelpers = import('core/widgets/widget_helpers.lua', nil, {
    logging = deps.logging,
    storage = deps.storage,
    actions = deps.actions,
    imguiHelpers = imguiHelpers,
    widgets = widgets,
})
import('core/widgets/base.lua', nil, widgetHelpers)
import('core/widgets/inputs.lua', nil, widgetHelpers)
import('core/widgets/dropdowns.lua', nil, widgetHelpers)
import('core/widgets/radios.lua', nil, widgetHelpers)
import('core/widgets/steppers.lua', nil, widgetHelpers)
import('core/widgets/checkboxes.lua', nil, widgetHelpers)
import('core/widgets/buttons.lua', nil, widgetHelpers)

local nav = import 'core/widgets/nav.lua'

---@class BoundWidgets
---@field separator fun()
---@field text fun(text: any, opts: TextOpts|nil)
---@field button fun(label: any, opts: ButtonOpts|nil): boolean
---@field confirmButton fun(id: string|number, label: any, opts: ConfirmButtonOpts|nil): boolean
---@field inputText fun(alias: string, opts: InputTextOpts|nil): boolean
---@field dropdown fun(alias: string, opts: DropdownOpts|nil): boolean
---@field mappedDropdown fun(alias: string, opts: MappedDropdownOpts|nil): boolean
---@field packedDropdown fun(alias: string, opts: PackedDropdownOpts|nil): boolean
---@field getPackedChoiceAlias fun(alias: string, opts: PackedDropdownOpts|PackedRadioOpts|nil): string|nil
---@field radio fun(alias: string, opts: RadioOpts|nil): boolean
---@field mappedRadio fun(alias: string, opts: MappedRadioOpts|nil): boolean
---@field packedRadio fun(alias: string, opts: PackedRadioOpts|nil): boolean
---@field stepper fun(alias: string, opts: StepperOpts|nil): boolean
---@field steppedRange fun(minAlias: string, maxAlias: string, opts: SteppedRangeOpts|nil): boolean
---@field checkbox fun(alias: string, opts: CheckboxOpts|nil): boolean
---@field packedCheckboxList fun(alias: string, opts: PackedCheckboxListOpts|nil): boolean

---@param imgui table
---@param session Session
---@return BoundWidgets
function widgets.bind(imgui, session)
    local function resolveField(target, methodName)
        return deps.storage.field.resolve(session, target, "draw.widgets." .. methodName)
    end

    local function callFieldWidget(methodName, target, opts)
        local field = resolveField(target, methodName)
        return widgets[methodName](imgui, field:owner(), field:alias(), opts)
    end

    return {
        separator = function()
            return widgets.separator(imgui)
        end,
        text = function(text, opts)
            return widgets.text(imgui, text, opts)
        end,
        button = function(label, opts)
            return widgets.button(imgui, label, opts)
        end,
        confirmButton = function(id, label, opts)
            return widgets.confirmButton(imgui, id, label, opts)
        end,
        inputText = function(target, opts)
            return callFieldWidget("inputText", target, opts)
        end,
        dropdown = function(target, opts)
            return callFieldWidget("dropdown", target, opts)
        end,
        mappedDropdown = function(target, opts)
            return callFieldWidget("mappedDropdown", target, opts)
        end,
        packedDropdown = function(target, opts)
            return callFieldWidget("packedDropdown", target, opts)
        end,
        getPackedChoiceAlias = function(target, opts)
            local field = resolveField(target, "getPackedChoiceAlias")
            return widgets.getPackedChoiceAlias(field:owner(), field:alias(), opts)
        end,
        radio = function(target, opts)
            return callFieldWidget("radio", target, opts)
        end,
        mappedRadio = function(target, opts)
            return callFieldWidget("mappedRadio", target, opts)
        end,
        packedRadio = function(target, opts)
            return callFieldWidget("packedRadio", target, opts)
        end,
        stepper = function(target, opts)
            return callFieldWidget("stepper", target, opts)
        end,
        steppedRange = function(minTarget, maxTarget, opts)
            local minField = resolveField(minTarget, "steppedRange")
            local maxField = resolveField(maxTarget, "steppedRange")
            if minField:owner() ~= maxField:owner() then
                deps.logging.violate("widgets.mismatched_field_owners",
                    "draw.widgets.steppedRange: min and max fields must share one storage owner"
                )
            end
            return widgets.steppedRange(imgui, minField:owner(), minField:alias(), maxField:alias(), opts)
        end,
        checkbox = function(target, opts)
            return callFieldWidget("checkbox", target, opts)
        end,
        packedCheckboxList = function(target, opts)
            return callFieldWidget("packedCheckboxList", target, opts)
        end,
    }
end

return {
    widgets = widgets,
    nav = nav,
    imguiHelpers = imguiHelpers,
}
