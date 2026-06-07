# One-Line Helper Audit

## Commands

```powershell
rg -n -U "local function \w+\([^\n]*\)\r?\n\s+return [^\n]+\r?\nend" src
rg -n -U "local function \w+\([^\n]*\)\r?\n\s+[^\n]+\([^\n]*\)\r?\nend" src
rg -n -U "function \w+\.\w+\([^\n]*\)\r?\n\s+return [^\n]+\r?\nend" src\core
```

## Classification

- `delete`: local helpers that only forwarded to `modutilHooks.installWrap` and
  `modutilHooks.installContextWrap` in `hooks/dispatchers.lua`. The direct calls
  are clearer and the helpers were also returned from the dispatcher module even
  though no caller used them.
- `collapse`: coordinator private functions plus public wrappers in the same
  file. The exported coordinator methods now carry the behavior directly.
- `keep`: public or framework-facing one-line methods that are intentional API
  facades, including hashing, managed-module registry accessors, module-state
  factory methods, widget helpers, storage predicates, and plan executors.
- `keep`: small predicates and name builders that make dense subsystem code read
  at the right abstraction level.
- `defer`: fallback UI's `createFallbackMarker` remains test-visible through the
  fallback UI service. Changing it belongs in a fallback-specific audit rather
  than this broad pass.

## Result

The obvious accidental wrappers were removed. Remaining one-line functions are
either named policy, public/internal API surfaces, registry accessors, or
subsystem factory seams.
