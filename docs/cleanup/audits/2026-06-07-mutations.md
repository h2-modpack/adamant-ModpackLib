# Mutation Audit

Scope:

```powershell
rg -n "mutation|mutations|module\.mutation|patchMutation|syncForModule|revertForModule|applyForModule|createPlan|appendUnique|removeElement|setElement|affectsRunData" src tests docs API.md README.md
rg -n "SetupRunData|setupRunData|applyForModule\(|revertForModule\(|syncForModule\(|commitStagedState|setEnabled|RunData" src\core tests\TestMutation_DefinitionLifecycle.lua tests\TestManagedModule.lua tests\TestHooks.lua
```

Files read:

- `src/core/mutations/00_init.lua`
- `src/core/mutations/plan.lua`
- `src/core/mutations/lifecycle.lua`
- `src/core/mutations/adapters/module_lifecycle.lua`
- `src/core/module_bootstrap/managed_module_lifecycle.lua`
- `src/core/module_bootstrap/managed_module_activation.lua`
- `src/core/fallback/fallback_ui.lua`
- Framework `src/core/ui/runtime.lua` and `src/core/ui/window.lua`
- `tests/TestMutation.lua`
- `tests/TestMutation_DefinitionLifecycle.lua`

## Summary

The mutation subsystem is conceptually coherent. It has one author-facing
declaration (`module.mutation.patch(...)`), one plan builder surface, and one
owner-keyed active-plan runtime. Activation uses the receipt model correctly:
candidate mutation state is committed before other managed effects, rollback can
restore the previous plan, and previous module retirement is delayed until the
replacement activation succeeds.

The main implementation shape should stay. The useful future work is small and
mostly about consistency.

## Findings

### fixed: `plan:setMany(...)` clones its input map at declaration time

`src/core/mutations/plan.lua:64` stores the caller-provided `kv` table directly.
Other plan operations clone values when the operation is declared. This means a
caller can mutate the `kv` table after building the plan but before apply, and
the mutation plan changes underfoot.

Implemented by storing `kv = values.deepCopy(kv)` in the operation and adding
`TestMutation:testPlanSetManyClonesInputMapOnDeclaration`.

### fixed: `plan:setElement(...)` docs used the wrong argument name

`docs/module-authors/capabilities/MUTATIONS.md:39` documents:

```lua
plan:setElement(tbl, key, index, value)
```

The implementation at `src/core/mutations/plan.lua:110` is old-value based:

```lua
plan:setElement(tbl, key, oldValue, newValue, equivalentFn)
```

The docs should describe the old-value/comparator behavior because that is the
actual useful contract for list patching.

Implemented by updating the operation list to:

```lua
plan:setElement(tbl, key, oldValue, newValue, equivalentFn)
```

### keep: recompute ownership is split intentionally, but should stay visible

`src/core/mutations/lifecycle.lua:164` activation sync recomputes run data
inside the mutation receipt. Normal settings commits go through
`src/core/module_bootstrap/managed_module_lifecycle.lua:178` and direct
`applyForModule(...)` / `revertForModule(...)`; Framework and fallback UI then
batch `SetupRunData()` externally when the module affects run data.

This is coherent: UI shells can coalesce recompute work for draw-time changes,
while activation needs its own self-contained transaction. The caveat is that
the direct live-module mutation methods should continue to be treated as
internal lifecycle helpers, not a general author-facing recompute API.

### collapse later: `lifecycle.sync(...)` receives an unused definition

`src/core/mutations/lifecycle.lua:164` accepts `def`, and
`src/core/mutations/adapters/module_lifecycle.lua:25` passes
`record.definition`, but the lifecycle no longer reads it. This is harmless.
It can be collapsed when the broader module lifecycle surface is audited.

## Coverage

Coverage is strong for:

- backup/restore behavior
- repeat-safe apply/revert
- transform cloning and error rollback
- list operations and custom comparators
- owner-keyed active plan replacement
- activation sync for enabled/disabled reloads
- enable/disable mutation rollback

Verification run:

```powershell
lua52.exe tests\all.lua TestMutation TestMutation_DefinitionLifecycle TestMutation_BackupSystem
luacheck src tests\TestMutation.lua
git diff --check
```
