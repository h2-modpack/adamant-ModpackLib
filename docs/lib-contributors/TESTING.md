# Testing

Lib tests should mirror the dependency graph in `src/core/init.lua` where that
makes subsystem behavior clearer. Prefer harness-created dependencies over
manual global snapshots or production APIs created only for tests.

## Local Lib Suite

Run the Lib suite from this package:

```bash
cd adamant-ModpackLib
lua5.2 tests/all.lua
```

Use targeted subsystem tests while iterating, then run the full suite before
finishing a Lib change.

## Shell Repo Suite

From the shell repo root, run:

```bash
ModpackTools/run ModpackTools/local_test/all.py
```

This is the high-signal local assembled-checkout validation path for the repo
family. It runs the same shell smoke command as shell CI, then runs each
registered repo's declared `tests/all.lua` or `tests/all.py` entrypoint when
present.

Shell repos keep `tests/smoke.lua` as a thin caller into
`tests/harness/shell_smoke.lua`. The shared harness derives the smoke layout
from `.gitmodules`, package metadata, and the coordinator `PACK_ID`, so shell
repos do not duplicate module-roster discovery logic.

## Module Test Boundary

Module tests should focus on module-owned behavior and game-facing effects, not
Lib internals. A module test may use tiny fakes for public author-facing Lib
APIs when the module production code naturally depends on those APIs, such as
`module.hooks.wrap(...)`, `module.mutation.patch(...)`,
`module.shared.data.owner(...)`, or `host.ui.tab(...)`. This small coupling is
intentional: if the public author API changes, module tests should fail early
and show that module migration work is needed.

Keep that coupling at the author API boundary. Module tests should not activate
a real Lib module just to inspect Lib-owned state, and should not fake or read
private Lib internals such as live-module records, staged state, persistent
backend state, activation receipts, mutation rollback machinery, registries, or
config hydration paths. Those concerns belong in Lib tests.

Good module tests assert externalities owned by the module:

- hook return values or argument mutations;
- patch plan intent emitted by module patch builders;
- shared-data snapshot shape authored by the module;
- data, control, UI, resolver, and pure logic behavior.

Shell-level entrypoint smoke tests own real compatibility with the current Lib
author and modpack surfaces. They should boot the real module and make broad
assertions such as module identity and callback registration, while detailed
state-machine, persistence, activation, and rollback behavior stays covered by
Lib tests.

## Diff Hygiene

Before finishing a doc or code change, run:

```bash
git diff --check
```

For architecture changes, also grep for retired names or stale public/internal
surfaces in both `src` and `tests`.
