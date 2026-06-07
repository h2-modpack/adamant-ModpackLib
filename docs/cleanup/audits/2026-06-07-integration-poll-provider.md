# Integration/Poll/Provider Vocabulary Audit

## Scope

Audit command:

```powershell
rg -n "\bintegration\b|\bintegrations\b|\bpoll\b|\bprovider\b|\bproviders\b|\bprovide\b|Integration|Integrations|Poll|Provider|Providers|Provide" src tests docs API.md
```

## Result

No live `integration` or `poll` API terminology remains outside historical audit
files. The old shared `provide`/`poll` negative assertions were removed from
tests because they described retired migration-era surfaces.

The shared implementation still uses supplier callbacks while staging
declarations/listeners, but those are named `getModule` rather than provider
terminology.

Remaining non-historical matches are ordinary English or rejected-design notes,
not current API vocabulary:

- overlays can `provide` a visibility callback
- rejected declarative UI notes mention option providers
- hook tests use `Provides` in the plain-English test name
