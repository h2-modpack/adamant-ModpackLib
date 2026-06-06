# Immediate-Mode UI Performance

Reference for writing or auditing module draw code without re-deriving render-path performance analysis from scratch.

This guidance applies to module draw code:
- `drawTab(host, ui)`
- optional `drawQuickContent(host, ui)`
- `draw.widgets.*`
- `draw.nav.*`
- `ui.controls.*`
- raw ImGui for structure

## Why Draw Paths Need Care

Module UI is immediate-mode:
- `drawTab(host, ui)`
- optional `drawQuickContent(host, ui)`

These run every imgui frame.
Any unnecessary allocation or repeated C-boundary call inside those paths shows up immediately.

## Contract Assumptions

This document assumes:
- raw `config` stays local to `main.lua`
- `lib.createModule(...)` owns the definition and state construction boundary
- draw code reads staged values through `ui.data.get(...)`
- runtime/gameplay code reads committed setting values through
  `runtime.data.get(...)`
- status values are written through `runtime.status` and read from UI through
  `ui.status`
- draw-callback objects are shaped by variant type; read methods are
  phase-neutral, while mutation methods remain scoped
- debug toggles write persisted values through the host/framework flow
- hash/profile import and config flush behavior belong to host/framework plumbing, not draw callbacks
- framework/host own staged-state commit timing
- fallback UI registers ROM callbacks through `module.fallbackUi.attachGuiOnce(...)`
  and installs the active runtime during `module.activate()`

## Per-Frame Checklist

### 1. Avoid string concatenation in hot draw loops

Bad:

```lua
draw.imgui.Text("Equipped: " .. tostring(currentWeapon))
```

Better:
- cache slow-changing derived strings
- or compute once per draw function, not repeatedly inside loops

If the text really is stable across many frames:
- cache it on module state
- invalidate that cache only when the source values change

### 2. Avoid inline table literals in draw paths

Bad:

```lua
local color = opts.color or { 1, 1, 1, 1 }
```

Better:
- use a module-level constant

This applies to:
- colors
- repeated option lists
- repeated tab definitions
- static label maps

### 3. Cache repeated ImGui getters inside one draw function

Bad:

```lua
draw.imgui.SetCursorPosX(draw.imgui.GetWindowWidth() * 0.5)
draw.imgui.PushItemWidth(draw.imgui.GetWindowWidth() * 0.3)
```

Better:

```lua
local imgui = draw.imgui
local winW = imgui.GetWindowWidth()
imgui.SetCursorPosX(winW * 0.5)
imgui.PushItemWidth(winW * 0.3)
```

Do the same for:
- `GetContentRegionAvail()`
- `GetFrameHeight()`
- `GetStyle().ItemSpacing.x` if you are already using it repeatedly in one function

### 4. Reuse `ui.data.get(...)` refs for repeated reads

Use:
- `local enabled = ui.data.get("Enabled")`
- `enabled:read()`

When a draw helper reads the same value multiple times, cache the field handle
inside that draw function and read through it.

### 5. Let host/framework own commit timing

Do not hand-roll flush logic inside draw code.

Ownership:
- framework-hosted modules commit after `drawTab` / `drawQuickContent`
- fallback UI modules should register GUI callbacks through
  `module.fallbackUi.attachGuiOnce(...)`; activation installs runtime state

The module's job is:
- render from `ui.data`
- stage edits into `ui.data`

Not:
- custom flush timing
- custom rollback timing

### 6. Keep layout immediate and local

Prefer:
- one readable draw flow
- small helper functions that directly draw
- direct ImGui for spacing, grouping, child regions, and tab bars

Avoid:
- rebuilding an internal retained layer
- introducing generic builder indirection just to avoid a few repeated lines

### 7. Keep dynamic option builders out of inner loops when possible

If a dropdown/radio option list only changes when one or two aliases change:
- compute it once per draw function
- or cache it off the relevant source state

Do not rebuild the same large option table multiple times in the same frame.

## Good Patterns

- use `draw.widgets.*` for common controls
- use `draw.nav.verticalTabs(...)` for simple vertical nav rails
- keep draw helpers local and concrete
- duplicate small UI when that makes render order clearer
- compute derived view text only when it actually improves readability
- keep packed-widget filtering data outside the innermost draw loop when practical

## Bad Patterns

- rebuilding unnecessary tables in hot loops
- caching abstractions that only survive one frame
- reintroducing retained/prepared UI layers for simple screens
- splitting one draw flow into extra lifecycle phases without a real need
- calling `runtime.data.get(...):read()` from draw code instead of reading staged values through `ui.data.get(...)`
- doing config writes directly from draw code instead of staging through `ui.data`
- bypassing the host/framework flow for normal widget edits




