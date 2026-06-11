# Testing

Lib tests should mirror the dependency graph in `src/core/init.lua` where that
makes subsystem behavior clearer. Prefer harness-created dependencies over
manual global snapshots or production APIs created only for tests.

## Local Lib Suite

Run the Lib suite from this package:

```bash
cd adamant-ModpackLib
lua52.exe tests/all.lua
```

Use targeted subsystem tests while iterating, then run the full suite before
finishing a Lib change.

## Shell Repo Suite

From the shell repo root, run:

```bash
python ModpackTools/test_all.py
```

This is the high-signal end-to-end validation path for the repo family. It runs
Lib, Framework, module, and ModpackTools tests through the shared test harness.

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

Shell-level entrypoint smoke tests own real compatibility with the current
Lib/Framework stack. They should boot the real module and make broad assertions
such as module identity and callback registration, while detailed state-machine,
persistence, activation, and rollback behavior stays covered by Lib tests.

## Diff Hygiene

Before finishing a doc or code change, run:

```bash
git diff --check
```

For architecture changes, also grep for retired names or stale public/internal
surfaces in both `src` and `tests`.
