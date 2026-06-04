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

## Diff Hygiene

Before finishing a doc or code change, run:

```bash
git diff --check
```

For architecture changes, also grep for retired names or stale public/internal
surfaces in both `src` and `tests`.
