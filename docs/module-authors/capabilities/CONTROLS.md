# Controls

Controls are module-declared composite UI/data objects.

Use them when one domain concept needs a small bundle of managed storage,
semantic runtime reads, and one or more standard draw paths. Keep ordinary leaf
UI on `ui.draw.widgets.*`.

## Declaration

Declare templates and instances before activation:

```lua
local RangeSelector = {}

function RangeSelector.storage(instance)
    return {
        { key = "Mode", type = "string", default = instance.defaultMode or "Any", maxLen = 32 },
        { key = "Min", type = "int", default = instance.defaultMin or 0, min = 0, max = 10 },
    }
end

function RangeSelector.createRuntime(fields)
    return {
        read = function(self)
            return {
                mode = fields.Mode:read(),
                min = fields.Min:read(),
            }
        end,
    }
end

function RangeSelector.createUi(fields)
    return {
        read = function(self)
            return {
                mode = fields.Mode:read(),
                min = fields.Min:read(),
            }
        end,
        field = function(self, key)
            return fields[key]
        end,
    }
end

function RangeSelector.draw(draw, control, instance, opts)
    draw.widgets.dropdown(control:field("Mode"), {
        label = opts.label or instance.label or "Mode",
        values = instance.values,
    })
    draw.widgets.stepper(control:field("Min"), {
        label = "Min",
    })
end

module.controls.defineTemplates({
    RangeSelector = RangeSelector,
})

module.controls.define({
    RewardPriority = {
        template = "RangeSelector",
        label = "Reward Priority",
        values = { "Any", "First", "Last" },
    },
})
```

`storage(...)` uses `key` instead of public `alias`. Lib compiles those keys to
private storage aliases, so normal `ui.data` and `runtime.data` cannot read or
write the generated fields directly.

## Runtime Use

Runtime callbacks use `runtime.controls`:

```lua
module.hooks.wrap("SomeGameFunction", function(host, runtime, base, ...)
    local priority = runtime.controls.read("RewardPriority")
    if priority.mode == "First" then
        host.logIf("first reward priority")
    end
    return base(...)
end)
```

`runtime.controls.get(name)` returns a cached runtime control ref.
`runtime.controls.read(name, ...)` calls that ref's `read(...)` method.

## Draw Use

Draw callbacks use `ui.controls` and `ui.draw.control(...)`:

```lua
local REWARD_PRIORITY_OPTS = {
    label = "Reward Priority",
}

local function drawTab(host, ui)
    ui.draw.control(ui.controls.get("RewardPriority"), "default", REWARD_PRIORITY_OPTS)
end
```

Template renderers receive:

```lua
function Template.draw(draw, control, instance, opts)
end
```

Named views are supported:

```lua
Template.views = {
    default = function(draw, control, instance, opts) end,
    compact = function(draw, control, instance, width) end,
}

ui.draw.control(ui.controls.get("RewardPriority"), "compact", 180)
```

Draw code can reset control-backed storage without exposing generated aliases:

```lua
ui.controls.reset("RewardPriority")
ui.controls.resetAll()
```

These helpers reset the Lib-compiled storage roots for the control instance.
They do not call template-defined reset methods.

## Rules

- Template and control names must be stable identifiers.
- Control refs are shaped for the callback surface that created them. Reads are
  phase-neutral; generated writable fields remain draw-scoped.
- Controls are not layout builders. The module still owns tab order, sections,
  catalogs, and screen composition.
- Do not use controls for one-off leaf fields. `ui.draw.widgets.*` is simpler.
- Do not use generated `_` aliases directly; they are private Lib storage.
