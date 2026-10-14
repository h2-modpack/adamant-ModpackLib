local deps = ...

local declarations = import('core/controls/declarations.lua', nil, {
    logging = deps.logging,
    identifiers = deps.identifiers,
})

local compiler = import('core/controls/compiler.lua', nil, {
    logging = deps.logging,
    values = deps.values,
    identifiers = deps.identifiers,
})

local refs = import('core/controls/refs.lua', nil, {
    logging = deps.logging,
    values = deps.values,
    storage = deps.storage,
    requireMethodSelf = deps.requireMethodSelf,
})

local draw = import('core/controls/draw_controls.lua', nil, {
    logging = deps.logging,
    refs = refs,
})

return {
    declarations = declarations,
    compiler = compiler,
    refs = refs,
    draw = draw,
}
