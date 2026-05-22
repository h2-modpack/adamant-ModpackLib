local deps = ...

local imguiHelpers = import 'core/widgets/imgui_helpers.lua'
local widgetHelpers = import('core/widgets/widget_helpers.lua', nil, {
    logging = deps.logging,
    storage = deps.storage,
    actions = deps.actions,
    imguiHelpers = imguiHelpers,
})
local baseWidgets = import('core/widgets/base.lua', nil, widgetHelpers)
local inputWidgets = import('core/widgets/inputs.lua', nil, widgetHelpers)
local dropdownWidgets = import('core/widgets/dropdowns.lua', nil, widgetHelpers)
local radioWidgets = import('core/widgets/radios.lua', nil, widgetHelpers)
local stepperWidgets = import('core/widgets/steppers.lua', nil, widgetHelpers)
local checkboxWidgets = import('core/widgets/checkboxes.lua', nil, widgetHelpers)
local buttonWidgets = import('core/widgets/buttons.lua', nil, widgetHelpers)

local widgets = {
    separator = baseWidgets.separator,
    text = baseWidgets.text,
    inputText = inputWidgets.inputText,
    dropdown = dropdownWidgets.dropdown,
    packedDropdown = dropdownWidgets.packedDropdown,
    getPackedChoiceAlias = dropdownWidgets.getPackedChoiceAlias,
    radio = radioWidgets.radio,
    packedRadio = radioWidgets.packedRadio,
    stepper = stepperWidgets.stepper,
    steppedRange = stepperWidgets.steppedRange,
    checkbox = checkboxWidgets.checkbox,
    packedCheckboxList = checkboxWidgets.packedCheckboxList,
    button = buttonWidgets.button,
    confirmButton = buttonWidgets.confirmButton,
}

local nav = import 'core/widgets/nav.lua'
local uiDraw = import('core/widgets/ui_draw.lua', nil, {
    widgets = widgets,
    nav = nav,
    logging = deps.logging,
    storage = deps.storage,
    rom = deps.rom,
})

return {
    widgets = widgets,
    nav = nav,
    uiDraw = uiDraw,
    imguiHelpers = imguiHelpers,
}
