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
---@field inputText fun(target: string|StorageField, opts: InputTextOpts|nil): boolean
---@field dropdown fun(target: string|StorageField, opts: DropdownOpts|nil): boolean
---@field packedDropdown fun(target: string|StorageField, opts: PackedDropdownOpts|nil): boolean
---@field getPackedChoiceAlias fun(target: string|StorageField, opts: PackedDropdownOpts|PackedRadioOpts|nil): string|nil
---@field radio fun(target: string|StorageField, opts: RadioOpts|nil): boolean
---@field packedRadio fun(target: string|StorageField, opts: PackedRadioOpts|nil): boolean
---@field stepper fun(target: string|StorageField, opts: StepperOpts|nil): boolean
---@field steppedRange fun(minTarget: string|StorageField, maxTarget: string|StorageField, opts: SteppedRangeOpts|nil): boolean
---@field checkbox fun(target: string|StorageField, opts: CheckboxOpts|nil): boolean
---@field packedCheckboxList fun(target: string|StorageField, opts: PackedCheckboxListOpts|nil): boolean

---@param imgui table
---@param session Session
---@return BoundWidgets
function widgets.bind(imgui, session)
    local function resolveField(target, methodName)
        return deps.storage.field.resolve(session, target, "draw.widgets." .. methodName)
    end

    local function callFieldWidget(methodName, target, opts)
        local field = resolveField(target, methodName)
        return widgets[methodName](imgui, field, opts)
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
        packedDropdown = function(target, opts)
            return callFieldWidget("packedDropdown", target, opts)
        end,
        getPackedChoiceAlias = function(target, opts)
            local field = resolveField(target, "getPackedChoiceAlias")
            return widgets.getPackedChoiceAlias(field, opts)
        end,
        radio = function(target, opts)
            return callFieldWidget("radio", target, opts)
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
            return widgets.steppedRange(imgui, minField, maxField, opts)
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
