# Known Limitations

This file documents current design constraints that are intentional or accepted for now.

These are not hidden bugs. They are boundaries the current architecture chooses to live with until the underlying runtime, Framework surface, or project requirements change.

## Structural Rebuilds Are Immediate

When a coordinated module changes its structural contract during hot reload, Lib requests a Framework rebuild as soon as the replacement host is published.

The module rebuild path is:

- `lib.createModule(...)`
- `module.activate()`
- requested fallback UI when running outside Framework coordination

The Framework rebuild is correct, but it is not coalesced across a multi-module reload wave.

Example:

- module A structurally reloads
- Framework rebuilds
- module B structurally reloads right after
- Framework rebuilds again

Why this exists:

- ReturnOfModdingBase reloads modules through an internal file-watcher queue
- that queue drain boundary is not exposed to Lua
- neither ROM nor ModUtil currently provides a clean "hot reload wave complete" callback

What would remove it:

- a ROM-side callback such as `mods.on_hot_reload_wave_complete(...)`
- or another clean Lua-visible boundary after `process_file_watcher_queue()` drains

## Infrastructure Hot Reload Is Best-Effort

Author-facing module hot reload is the supported fast path. Lib and Framework hot reload are infrastructure development paths, with a full game process restart as the correctness boundary.

What this means in practice:

- existing managed modules may close over prior Lib implementation closures until the owning module reloads
- active mutation runtime is durable across module reload, not arbitrary Lib implementation reload
- a Framework file reload does not update an existing pack object until a coordinator rebuild calls `Framework.createPack(...)` again
- retained HUD layout changes may require HUD recreation or a game HUD refresh

Why this exists:

- fully live infrastructure reload would require more persistent dispatch machinery and durable mutation bookkeeping across Lib reloads
- that complexity is not justified by normal module-author workflows
- infrastructure edits are less frequent and can use full process restart for correctness validation

What would remove it:

- persistent Lib mutation runtime across Lib implementation reloads
- managed-module methods routed through stable late-bound Lib dispatch
- an explicit infrastructure reload protocol that forces module and Framework convergence

## Module Activation Rollback Covers Managed Effects Only

Lib module activation is designed to keep the old live module active until the replacement module has usable managed runtime effects.

What this means in practice:

- failed activation preserves the old live module when rollback succeeds
- Lib-managed hooks, shared events, overlays, patch mutation state, and live-module publication participate in activation cleanup
- omitted managed registrations are cleaned up during successful module reload
- direct module writes to game globals, ROM APIs, ModUtil APIs, or other public environment state are outside Lib rollback
- system overlays are trusted first-party infrastructure, not a general transactional owner surface

Why this exists:

- Lua modules cannot be physically sandboxed from game globals or platform APIs
- ModUtil and ROM do not expose complete undo handles for every possible side effect
- making every subsystem independently transactional would add more complexity than the supported module hot-reload path justifies
- system overlays exist only for narrow Lib/Framework HUD lines and avoid exposing a broad owner-token escape hatch

What would remove it:

- a stricter sandboxed module execution environment
- platform APIs that provide reliable undo handles for all runtime effects
- or a project decision to trade substantially more internal complexity for recovery from obscure broken dev-reload states

## Fallback UI Attachment Is Callsite-Bound

Fallback module UI uses stable callbacks from `module.fallbackUi.attachGuiOnce(...)`, but the ROM GUI callback attachment still belongs in module code.

What this means in practice:

- `rom.gui.add_imgui(...)` and `rom.gui.add_to_menu_bar(...)` must run from the module's own callsite
- Lib can swap the runtime behind the bridge after `module.activate()`
- Lib cannot fully fold ROM GUI callback attachment into managed module activation
- fallback UI runtime cleanup is host-owned after activation, but the original ROM callback attachment is not an activation receipt

Why this exists:

- ROM associates GUI callbacks with the module callsite that performs the attachment
- shared Lib code cannot attach GUI callbacks on behalf of an arbitrary feature module even when it has that module's `pluginGuid`

What would remove it:

- a ROM API that lets Lib attach GUI callbacks for an explicit plugin identity
- or a ROM/module-loader contract that lets Lib attach GUI callbacks without losing module attribution

## Mutation Recompute Is Per Operation And Best-Effort

Patch-plan mutation edits raw game tables, then Lib asks the game to recompute derived run data with `SetupRunData()`.

What this means in practice:

- v1 has no mutation batch mode; each activation, profile load, enable/disable, or staged-state/runtime transition owns its own recompute
- `SetupRunData()` is treated as a trusted base-game recompute boundary, not an atomic commit primitive
- if candidate mutation activation fails, Lib attempts to restore the prior raw patch state and keep the old module live
- if the base-game recompute or rollback recompute fails, derived game state can be uncertain until restart or another clean game recompute

Why this exists:

- game data table edits and live derived run-data refresh are separate operations
- `SetupRunData()` is base-game behavior, not Lib-owned transaction machinery
- batching recomputes would add coordination complexity before the simpler per-operation model has demonstrated a real bottleneck

What would remove it:

- a base-game or ROM-provided atomic run-data transaction API
- a demonstrated performance or correctness need for mutation batch mode
- or a broader runtime coordinator that intentionally batches multiple module mutation transitions

## Private Module `internal` Usage Is Convention-Driven

Lib provides clean state funnels for module authors:

- prepared definitions for structural contract
- managed storage for persisted state
- transient draw state for UI/runtime staging
- host methods for behavior

But private module `internal` tables remain module-owned implementation detail. Lib does not enforce what authors store there.

Why this exists:

- `internal` is intentionally flexible module-private composition state
- trying to centrally structure or lock it down would fight legitimate module-local implementation needs

What this means in practice:

- first-party modules should use transient draw state for real UI state
- private `internal` caching is still possible, even when it is less clean
- enforcement here is by convention, review, and first-party examples, not runtime guards

What would remove it:

- a more opinionated module-internal framework layer
- which is currently considered more complexity than the problem justifies

## No General Purpose Non-UI Per-Frame Lua Callback

ROM exposes:

- `gui.add_imgui(...)`
- `gui.add_always_draw_imgui(...)`
- `gui.add_to_menu_bar(...)`

These are useful, but they are still render/UI-oriented hooks. There is no clean general-purpose Lua `on_update` or `on_tick` callback for pack logic.

Why this matters:

- it makes deferred rebuild scheduling or end-of-frame coordination awkward
- UI callbacks are the wrong abstraction for non-UI pack orchestration

What would remove it:

- a ROM-side per-frame logic callback
- or a dedicated post-hot-reload drain callback

## Some Removed Hooks Can Leave Inert Wrappers

Lib hook dispatch prevents normal hot reload from stacking active wrappers for stable owner-id/path/key registrations.

One development-only caveat remains: if the same wrap or context-wrap site is removed, hot reloaded, re-added, and hot reloaded again within one live game process, an inert wrapper can remain until restart.

Why this exists:

- ModUtil path wraps are compositional and do not expose precise removal for every wrapper shape
- Lib can make omitted registrations inert, but cannot always erase the ModUtil wrapper already installed

What would remove it:

- ModUtil support for keyed wrapper replacement/removal
- or a full process restart, which clears wrapper chains

## Thunderstore Dependency Pins Are Edge Checks

Thunderstore resolves package dependencies to the latest available version for a package, not to the exact source snapshot checked out in a shell repo.

What this means in practice:

- package manifests must declare the required dependency edges
- shell release validation checks that required dependency edges are present
- release validation does not require the dependency pin in each `thunderstore.toml` to equal the checked-out source package version
- lower dependency pins can be intentional compatibility metadata, not release drift

Why this exists:

- package resolution is owned by Thunderstore
- the shell repo owns a source snapshot through submodule pointers
- those are related release surfaces, but they are not the same contract

What would remove it:

- exact dependency-version resolution support from Thunderstore
- or a project policy that intentionally pins every package dependency to the currently checked-out source version before each release

## Trusted Runtime Boundaries Are Not Locally Revalidated

The stack treats established runtime systems as trusted boundaries after startup-time runtime binding has succeeded. This includes the base game function reached through `base(...)`, ROM APIs, ImGui, ModUtil, Chalk, ENVY, and ReLoad.

What this means in practice:

- Lib and modules validate data and callbacks at their own public boundaries
- internal calls do not repeatedly revalidate trusted runtime APIs before every use
- wrappers may temporarily adjust module or game state before calling `base(...)`
- wrappers restore that temporary state after normal base-game calls
- wrappers do not attempt to recover from exceptions thrown by trusted runtime code itself
- a trusted-runtime failure is treated as a broader runtime failure that needs restart or upstream investigation

Why this exists:

- `base(...)` is the original game behavior being wrapped
- ROM, ImGui, ModUtil, Chalk, ENVY, and ReLoad are platform dependencies, not Lib-owned data
- adding local recovery around every trusted runtime call would add defensive noise to hot paths
- failures inside trusted runtime code are outside Lib and module ownership

What would remove it:

- a demonstrated recoverable base-game failure mode that Lib can handle generically
- a demonstrated recoverable platform failure mode that Lib can handle generically
- or a project policy that every trusted runtime call must use explicit protected-call cleanup
