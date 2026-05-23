# Pack Enable Suspension Spec

This note tracks the move from Framework-level effective disable to normal
module lifecycle transitions for pack enable/disable.

## Goal

Pack disable should suspend modules through Lib-owned host lifecycle methods,
and pack enable should restore the module enabled state that existed before
suspension. This keeps mutations, integrations, overlays, and provider
availability notifications on one lifecycle path.

## Internal Restore Storage

Lib injects a reserved built-in alias:

```lua
{
    type = "int",
    alias = "AdamantFramework_PackRestoreSnapshot",
    default = 0,
    min = 0,
    max = 2,
    hash = false,
}
```

Values:

- `0`: no restore snapshot
- `1`: restore disabled
- `2`: restore enabled

All aliases use the normal public identifier rule. Authors cannot declare
reserved built-in aliases.

Framework must not read or write this alias directly. The alias is a private
Lib persistence detail behind the `ModuleHost` pack-transition methods.

## Framework Disable

For each coordinated module:

1. Call `host.suspendForPackDisable()`.
2. Store the returned opaque rollback receipt for the Framework batch.

The pack-level `config.ModEnabled` flag is updated only after the batch
succeeds.

## Framework Disabled Startup

When a pack is created while `config.ModEnabled == false`, Framework reconciles
each discovered module through `host.ensureSuspendedForPackDisable()`. This
preserves any existing restore marker while ensuring raw module `Enabled` state
is disabled, so a full game restart while the pack is disabled does not
reactivate module runtime effects.

## Framework Enable

For each coordinated module:

1. Open the pack gate before restoring modules.
2. Call `host.restoreForPackEnable()`.
3. Store the returned opaque rollback receipt for the Framework batch.

The restore marker is persisted in module config, so pack suspension survives
full game restart.

## Rollback

Framework owns batch rollback:

- If disable fails, call `host.rollbackPackTransition(receipt)` for touched
  modules while the pack gate is still in its previous state.
- If enable fails, first disable touched modules while the pack gate is open so
  any restored effects are reverted, then close the pack gate and call
  `host.restorePackTransitionState(receipt)` for touched modules. This restores
  persisted module state without applying runtime effects while the pack remains
  disabled.

Rollback receipts are opaque to Framework. Lib owns the restore marker and
module enabled-state persistence details.

## Integration Semantics

`providerChanged` remains Lib-owned. Pack disable/enable triggers it naturally
because Framework drives modules through host lifecycle methods.

## Implementation Steps

1. Add `AdamantFramework_PackRestoreSnapshot` as a reserved built-in storage alias.
2. Update definition/storage tests for reserved built-ins.
3. Add host lifecycle pack-transition methods that hide restore marker details.
4. Add Framework module-registry helpers that call those host methods.
5. Rewrite pack disable/enable runtime flow to suspend/restore module state.
6. Add disabled-pack startup reconciliation.
7. Add rollback coverage.
8. Update author docs and changelog.
