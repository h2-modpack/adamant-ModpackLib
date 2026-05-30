local deps = ...

local logging = deps.logging
local phaseGate = deps.phaseGate
local refs = deps.refs

local drawControls = {}

function drawControls.render(draw, control, viewName, ...)
    phaseGate.requireAnyDraw()
    local entry = refs.getEntry(control)
    if entry == nil then
        logging.violate("controls.invalid_render_target", "ui.draw.control expects a control ref")
    end

    viewName = viewName or "default"
    local renderer = entry.views and entry.views[viewName] or nil
    if type(renderer) ~= "function" then
        logging.violate("controls.unknown_view", "control '%s': unknown view '%s'",
            tostring(entry.name), tostring(viewName))
    end

    return renderer(draw, control, entry.instance, ...)
end

return drawControls
