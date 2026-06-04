# Contributing to adamant-ModpackLib

`adamant-ModpackLib` owns the shared module contract for the modpack stack.

Keep the public surface:
- small
- explicit
- namespaced
- aligned with immediate-mode module authoring

## Read This First

- [README.md](README.md)
- [API.md](API.md)
- [docs/lib-contributors/LIB_INTERNALS.md](docs/lib-contributors/LIB_INTERNALS.md)
- [docs/lib-contributors/HOT_RELOAD_ARCHITECTURE.md](docs/lib-contributors/HOT_RELOAD_ARCHITECTURE.md)
- [docs/lib-contributors/TESTING.md](docs/lib-contributors/TESTING.md)
- [docs/module-authors/MODULE_AUTHORING.md](docs/module-authors/MODULE_AUTHORING.md)

## Contribution Rules

- Do not widen the public API casually.
- Keep docs aligned with code in the same change.
- Document the supported contract directly.
- Keep storage schema behavior behind `lib.createModule(...)` / internal storage; keep UI authoring on the draw object through `draw.widgets` / `draw.nav`.
- Unknown module misuse may warn and degrade where intended. Lib-owned contract breakage should fail loudly.

## Validation

```bash
cd adamant-ModpackLib
lua52.exe tests/all.lua
```

For shell-repo validation, run:

```bash
python ModpackTools/test_all.py
```
