local deps = ...

local declarations = import('core/controls/declarations.lua', nil, {
    logging = deps.logging,
})

local compiler = import('core/controls/compiler.lua', nil, {
    logging = deps.logging,
    values = deps.values,
})

local refs = import('core/controls/refs.lua', nil, {
    logging = deps.logging,
    values = deps.values,
    storage = deps.storage,
    phaseGate = deps.phaseGate,
})

local draw = import('core/controls/draw_controls.lua', nil, {
    logging = deps.logging,
    phaseGate = deps.phaseGate,
    refs = refs,
})

return {
    declarations = declarations,
    compiler = compiler,
    refs = refs,
    draw = draw,
}
