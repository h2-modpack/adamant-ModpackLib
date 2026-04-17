# Contributing to adamant-ModpackLib

`adamant-ModpackLib` owns the shared module contract for the modpack stack.

Keep the public surface:
- small
- explicit
- namespaced
- aligned with the current immediate-mode authoring model

## Read This First

- [README.md](README.md)
- [API.md](API.md)
- [MODULE_AUTHORING.md](MODULE_AUTHORING.md)
- [WIDGETS.md](WIDGETS.md)

## Contribution Rules

- Do not widen the public API casually.
- Keep docs aligned with code in the same change.
- Prefer documenting the live contract over preserving old migration history.
- Do not reintroduce declarative UI-tree abstractions unless the runtime really needs them again.
- Keep storage typing in `lib.storage`; keep UI authoring in `lib.widgets` / `lib.nav`.
- Unknown module misuse may warn and degrade where intended. Lib-owned contract breakage should fail loudly.

## Validation

```bash
cd adamant-ModpackLib
lua5.2 tests/all.lua
```
