# System Infrastructure

This document explains how ModpackLib, Framework, module authors, and external runtime systems fit together.

## Stack Overview

```mermaid
flowchart TD
    ROM["Hades II / ROM Runtime"]
    ENVY["ENVY imports"]
    MODUTIL["ModUtil hooks"]
    CHALK["Chalk config"]
    RELOAD["ReLoad lifecycle"]

    LIB["adamant-ModpackLib"]
    FRAMEWORK["adamant-ModpackFramework"]
    CORE["RunDirector Core"]
    MODULES["Feature Modules"]

    ROM --> ENVY
    ROM --> MODUTIL
    ROM --> CHALK
    ROM --> RELOAD

    ENVY --> LIB
    MODUTIL --> LIB
    CHALK --> LIB
    RELOAD --> LIB

    LIB --> FRAMEWORK
    LIB --> CORE
    LIB --> MODULES

    FRAMEWORK --> CORE
    FRAMEWORK --> MODULES
```

## Lib Composition Root

`src/core/init.lua` is the Lib composition root. It creates the shared runtime anchor, imports external dependencies, constructs services, and passes explicit dependencies into subsystems.

```mermaid
flowchart TD
    INIT["core/init.lua<br/>composition root"]

    INIT --> INPUTS
    INIT --> BASE
    INIT --> STATE
    INIT --> RUNTIME_SYS
    INIT --> UI_HOST

    subgraph INPUTS["Inputs"]
        direction TB
        RUNTIME["runtime anchor<br/>hot-reload stable"]
        EXTERNALS["externals<br/>rom / modutil / chalk / config"]
        GAMEDEPS["game deps<br/>scoped game functions/tables"]
    end

    subgraph BASE["Base Services"]
        direction TB
        LOGGING["logging"]
        VALUES["values"]
        STORAGE["storage"]
        HASHING["hashing"]
    end

    subgraph STATE["Module State"]
        direction TB
        MODULESTATE["module state<br/>store / session"]
        HOSTREGISTRY["host registry<br/>live host records"]
        COORD["coordinator"]
    end

    subgraph RUNTIME_SYS["Runtime Capabilities"]
        direction TB
        INTEGRATIONS["integrations"]
        HOOKS["hooks"]
        OVERLAYS["overlays"]
        MUTATIONS["mutations"]
    end

    subgraph UI_HOST["UI / Host"]
        direction TB
        HOST["module host"]
        FALLBACK_UI["fallback UI"]
        WIDGETS["widgets / nav"]
    end

    INPUTS --> BASE
    BASE --> STATE
    STATE --> RUNTIME_SYS
    RUNTIME_SYS --> UI_HOST

    RUNTIME -. hot reload state .-> STATE
    RUNTIME -. hot reload state .-> RUNTIME_SYS
    RUNTIME -. hot reload state .-> UI_HOST
```

## Module Lifecycle

Module authors normally touch only `lib.createModule(...)`, callbacks, and `host.activate()`.

```mermaid
sequenceDiagram
    participant Module as Module main.lua
    participant Lib as ModpackLib
    participant State as Store/Session
    participant Host as Module Host
    participant Effects as Hooks/Overlays/Integrations/Mutations
    participant Framework as Framework/Fallback UI

    Module->>Lib: lib.createModule(opts)
    Lib->>Lib: prepareDefinition(definition)
    Lib->>State: create store/session
    Lib->>Host: create ModuleHost + AuthorHost
    Lib-->>Module: authorHost, store

    Module->>Host: host.activate()
    Host->>Effects: install registrations
    Effects-->>Host: receipts
    Host->>Framework: publish live host
    Framework->>Host: drawTab / drawQuickContent
```

## Runtime Ownership

Persistent globals are only for hot-reload-stable anchors. Normal dependencies move through explicit composition.

```mermaid
flowchart LR
    GLOBAL["Global runtime anchor"]
    SERVICES["Explicit service objects"]
    PUBLIC["Public Lib API"]
    AUTHORS["Module author callbacks"]

    GLOBAL --> HOOKSTATE["hook dispatchers"]
    GLOBAL --> OVERLAYSTATE["overlay registries"]
    GLOBAL --> INTEGRATIONSTATE["integration providers"]
    GLOBAL --> MUTATIONSTATE["active mutation plans"]
    GLOBAL --> HOSTREGISTRY["host registry"]

    SERVICES --> PUBLIC
    PUBLIC --> AUTHORS

    AUTHORS -.->|"do not access"| GLOBAL
```

## Author vs Contributor Surface

```mermaid
flowchart TD
    AUTHOR["Module author"]
    CONTRIBUTOR["Lib contributor"]

    AUTHOR --> CREATE["createModule"]
    AUTHOR --> SESSION["session in draw callbacks"]
    AUTHOR --> STORE["store in runtime callbacks"]
    AUTHOR --> CAPABILITIES["hooks / mutations / overlays / integrations / widgets / cache"]

    CONTRIBUTOR --> INIT["core/init.lua composition"]
    CONTRIBUTOR --> SERVICES["subsystem services"]
    CONTRIBUTOR --> RUNTIME["runtime anchors"]
    CONTRIBUTOR --> TESTS["harness + subsystem tests"]

    AUTHOR -. "does not own" .-> RUNTIME
    AUTHOR -. "does not call private session methods" .-> SERVICES
```

## Design Rules

- Validate broad shape at contact points.
- Trust prepared internal values after construction.
- Pass dependencies explicitly.
- Use hot-reload runtime anchors only for state that must survive reload.
- Keep module author APIs separate from Lib contributor internals.
- Prefer capability guides for module-facing behavior and `API.md` for exact surface.
