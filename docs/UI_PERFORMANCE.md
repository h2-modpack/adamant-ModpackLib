# Immediate-Mode UI Performance

Reference for writing or auditing module draw code without re-deriving render-path performance analysis from scratch.

This guidance applies to module draw code:
- `DrawTab(ui, session)`
- optional `DrawQuickContent(ui, session)`
- `lib.widgets.*`
- raw ImGui for structure

## Why Draw Paths Need Care

Module UI is immediate-mode:
- `DrawTab(ui, session)`
- optional `DrawQuickContent(ui, session)`

These run every imgui frame.
Any unnecessary allocation or repeated C-boundary call inside those paths shows up immediately.

## Contract Assumptions

This document assumes:
- raw `config` stays local to `main.lua`
- `local definition = lib.prepareDefinition(...)` and `local store, session = lib.createStore(config, definition)` are the contract/state boundaries
- draw code reads staged values from `session.view`
- runtime/gameplay code reads persisted values through `store.read(...)`
- debug toggles write persisted values through `lib.lifecycle.setDebugMode(store, ...)`
- hash/profile plumbing stages arbitrary values through `session.write(...)` and flushes with `session._flushToConfig()`
- framework/host own `session` commit timing
- standalone UI goes through `lib.standaloneHost(...)`

## Per-Frame Checklist

### 1. Avoid string concatenation in hot draw loops

Bad:

```lua
ui.Text("Equipped: " .. tostring(currentWeapon))
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
ui.SetCursorPosX(ui.GetWindowWidth() * 0.5)
ui.PushItemWidth(ui.GetWindowWidth() * 0.3)
```

Better:

```lua
local winW = ui.GetWindowWidth()
ui.SetCursorPosX(winW * 0.5)
ui.PushItemWidth(winW * 0.3)
```

Do the same for:
- `GetContentRegionAvail()`
- `GetFrameHeight()`
- `GetStyle().ItemSpacing.x` if you are already using it repeatedly in one function

### 4. Default to `session.view` for reads

Use:
- `session.view.SomeAlias`

Prefer this over raw mutable staging values unless you have a concrete reason not to.

### 5. Let host/framework own commit timing

Do not hand-roll flush logic inside draw code.

Ownership:
- framework-hosted modules commit after `DrawTab` / `DrawQuickContent`
- standalone modules should go through `lib.standaloneHost(...)`

The module’s job is:
- render from `session`
- stage edits into `session`

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

- use `lib.widgets.*` for common controls
- use `lib.nav.verticalTabs(...)` for simple vertical nav rails
- keep draw helpers local and concrete
- duplicate small UI when that makes render order clearer
- compute derived view text only when it actually improves readability
- keep packed-widget filtering data outside the innermost draw loop when practical

## Bad Patterns

- rebuilding unnecessary tables in hot loops
- caching abstractions that only survive one frame
- reintroducing retained/prepared UI layers for simple screens
- splitting one draw flow into extra lifecycle phases without a real need
- calling `store.read(...)` repeatedly inside draw code for values already present in `session.view`
- doing config writes directly from draw code instead of staging through `session`
- using `lib.lifecycle.setDebugMode(...)` from draw code for normal widget edits




