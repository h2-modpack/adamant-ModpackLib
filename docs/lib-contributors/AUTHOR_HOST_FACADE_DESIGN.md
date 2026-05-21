# Author Host Facade Design

## Purpose

This note describes the proposed direction for module-author APIs in
ModpackLib.

The goal is to keep Lib backends stateless while making the module-facing API
host-shaped. Normal module authors should primarily learn:

1. create a host
2. declare module-owned capabilities on that host
3. activate the host

Capability implementations can remain isolated, testable, and mostly stateless
behind that facade.

## Status

This note remains useful for the host-owned capability direction. Its older
host-shaped draw examples are superseded by
[`DRAW_STORE_ACTION_DESIGN.md`](DRAW_STORE_ACTION_DESIGN.md): live module UI
uses `drawTab(draw, data, actions, services)`, where `draw` owns rendering
helpers and the other draw-phase objects are explicit callback arguments. It
does not receive the author host.

## Current Pressure

The runtime model is already host-centered. Host activation owns:

- live-host publication
- hot-reload replacement
- hooks
- overlays
- integration provider ownership
- mutation sync and rollback
- session commit and runtime refresh
- draw dispatch

The module-author API used to be less cohesive. Authors created a host, then
used a mix of callback contracts and global Lib namespaces:

```lua
drawTab(draw)
registerHooks(host, store)
registerPatchMutation(plan, host, store)
host.integrations.register(...)
host.integrations.invoke(...)

lib.hooks.*
lib.mutation.*
lib.widgets.*
```

That worked, but it created a bifurcated design:

- Lib and Framework manage module lifecycle through a host-like object.
- Module authors interact with a host plus many separate global service
  surfaces.

The accepted design makes the module-facing API match the runtime shape without
making Lib itself stateful. Hooks, integrations, cache, and retained module
overlays are already host-owned author surfaces; mutation and draw-related
surfaces remain migration candidates.

## Core Direction

Lib remains the stateless backend and construction namespace.

The author host becomes the module-facing bound facade:

```lua
local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})

host.hooks.wrap("SomeGameFunction", function(base, ...)
    if host.store.read("FeatureEnabled") then
        -- runtime behavior
    end
    return base(...)
end)

host.mutation.patch(function(plan, host, store)
    if store.read("PatchEnabled") then
        plan:set(SomeGameTable, "Enabled", true)
    end
end)

host.overlays.createLine("summary", {
    region = "middleRightStack",
})

host.integrations.register("run-director.some-provider", {
    providerId = MODULE_ID,
    api = {
        isAvailable = function()
            return host.store.read("FeatureEnabled") == true
        end,
    },
})

host.activate()
```

Draw code receives the same author host:

```lua
function ui.drawTab(host)
    host.widgets.checkbox("FeatureEnabled", {
        label = "Enabled",
    })

    host.imgui.Separator()
end
```

The public lesson becomes:

```text
create host -> declare capabilities -> activate host
```

## Vocabulary

Use these role names when discussing the implementation:

- `ModuleHost`: the full Lib object created by `moduleHost.create(...)`. It is
  the Framework/runtime surface for activation, replacement, commit, sync,
  rollback, mutation transitions, staged writes, and Framework draw entrypoints.
- `live module host`: an activated `ModuleHost` published in the live-host
  registry and consumed by Framework or fallback UI.
- `AuthorHost`: module-facing facade. It owns author capability declarations
  and exposes scoped draw/runtime surfaces.

The author host is not merely a subset of the `ModuleHost`. They are two
views over one module runtime. Some methods overlap, such as identity, metadata,
logging, enabled state, and activation handoff, but their responsibilities are
different.

User-facing docs may simply call the author-facing object `host`; module
authors do not need to learn the internal distinction up front. Treat
`lifecycle` as a responsibility of `ModuleHost`, not as the canonical type name.

## Lib Surface Target

The long-term public Lib surface should be much smaller for normal module
authors.

Expected public Lib responsibilities:

- host construction through `lib.createModule(...)`
- hosting/bootstrap helpers
- neutral utilities
- advanced escape hatches

Normal module-owned capabilities should move behind author-host namespaces:

- `host.hooks.*`
- `host.overlays.*`
- `host.integrations.register(...)`
- `host.mutation.*`
- `host.widgets.*`
- `host.nav.*`

Existing global capability APIs may remain during migration. They should not be
the destination authoring model.

## Capability Bundle Shape

Capability modules should return a named audience bundle. This is the standard
shape for migrated capabilities and the checklist to audit against.

Do not mutate `public` from a subsystem file. Do not mix author wrappers,
public exports, and backend internals into one generic service table. A
capability module should describe its audiences explicitly:

```lua
return {
    service = service,
    author = authorApi,
    framework = frameworkApi,
    public = publicApi,
}
```

Audience names have strict meanings:

- `service`: trusted backend used by Lib lifecycle and other internals.
- `author`: factories for host-bound author facades.
- `framework`: Framework-only runtime helpers exposed through
  `lib.createFrameworkRuntime(...)`.
- `public`: remaining `lib.*` exports, if that subsystem still has any.

Subsystems omit audiences they do not expose. The bundle should not include
empty audience tables just to satisfy the shape.

`core/init.lua` is the composition root. It mounts `public` exports, passes
`author` factories into `AuthorHost`, and passes `service` objects to internal
runtime owners. This keeps the public Lib surface visible in one place and
prevents subsystem imports from changing global API shape as a side effect.

The audience split is not ceremony. It answers three different questions:

- what Lib internals call (`service`)
- what module authors receive through `host.*` (`author`)
- what Framework receives through its runtime object (`framework`)
- what remains directly callable as `lib.*` (`public`)

Two current examples anchor the intended outcomes:

- `cache` returns `service` and `author`. It has no public `lib.cache`
  author API because cache access is owner-bound through `host.cache`.
- `integrations` returns `service` and `author`. Provider registration is
  owner-bound through `host.integrations.register(...)`, while consumers invoke
  through `host.integrations.invoke(...)`.
- `hashing` returns `framework`. It has no `service` audience because Lib
  internals do not consume the hashing helpers; Framework receives them through
  `frameworkRuntime.hashing`.

Audit rule: if a migrated capability exposes a callable table, reviewers should
be able to classify each method as exactly one of `service`, `author`,
`framework`, or `public`. If a method fits more than one audience, split the
wrapper from the backend instead of widening a shared table.

For non-trivial capabilities, split implementation files along the same
boundary:

- domain-named implementation files, such as `current_run_cache.lua`:
  stateless backend logic and backend-owned validation. Avoid generic names
  like `core.lua`.
- `adapter_author.lua`: host-bound adapter factories. These validate
  managed-host access,
  extract host-owned state such as `host.getHostId()`, and pass explicit state
  into the backend.
- `adapter_host.lua`: internal lifecycle-host adapter when Lib runtime code
  still needs host-shaped service methods such as `applyForHost(...)`. These
  should prove managed-host access, unpack host state, and delegate to explicit
  backend functions.
- `adapter_public.lua`: remaining direct `lib.*` bridge when a capability still
  exposes public functions. Public adapters should validate at the public call
  boundary or delegate to a backend that does.
- `adapter_framework.lua`: Framework-runtime adapter when Framework needs a
  helper that normal module authors should not receive directly.
- the subsystem entrypoint, such as `cache.lua`: composition only. It
  imports the backend and adapter, builds the audience bundle, and wires runtime
  dependencies.

Adapters should not duplicate backend validation. Their job is to prove and
unwrap the host; backend code owns subsystem semantics. Mutations are the
reference example for a capability that needs both `adapter_author.lua` and
`adapter_host.lua`; integrations are the reference example for a capability
that needs all three adapter audiences. Hooks are the reference example for a
capability with host/author adapters plus an internal physical-install service
used by another subsystem.

Identity boundary:

- `pluginGuid` is the module bootstrap/runtime identity. It belongs in
  `createModule(...)`, live-host lookup, plugin metadata, hot-reload
  comparison, and module-host adapters.
- `ownerId` is the capability-subsystem identity. Stateless subsystem logic
  should only know that it received a stable unique owner key; it should not
  know whether that owner is a module host, Framework system, Lib system, or
  future internal owner.
- Module-host adapters translate by reading `host.getHostId()` and passing the
  result into subsystem backends as `ownerId`.
- System adapters do not pretend to be plugins. They use the explicit
  `ownerId` stored on the managed system scope.
- System owner ids must be deliberately scoped, such as
  `adamant-lib.overlays.renderer` or `adamant-framework.<pack>.hud`, because
  system owners and module-backed owners share capability owner namespaces.

## Phase Model

Host capability declarations are immutable once activated.

The lifecycle has three author-visible phases:

```text
creation phase:
  author host exists
  capability declaration namespaces are open

activation:
  Lib snapshots and installs declared capabilities

activated phase:
  capability declaration namespaces reject new declarations
  draw/runtime/event facades open only during Lib-owned invocation windows
  lifecycle and status methods remain usable
```

Declaration surfaces that close after activation:

- `host.hooks.*`
- `host.overlays.create*`
- `host.overlays.on*`
- `host.integrations.register(...)`
- `host.mutation.patch(...)`

Runtime/status methods may remain usable after activation:

- `host.isEnabled()`
- `host.getHostId()`
- `host.getModuleId()`
- `host.getPackId()`
- `host.getMeta()`
- `host.log(...)`
- `host.logIf(...)`

The exact activation idempotency and retry behavior should remain owned by the
host lifecycle implementation.

## State Surfaces

Do not collapse staged and committed state into one phase-polymorphic
`host.read(...)`.

Keep the central state invariant visible:

```text
UI intent is staged.
Runtime behavior is committed.
```

Potential future author surfaces:

- `host.session`: staged UI state, available during draw.
- `host.store`: committed runtime state facade, available during sanctioned
  runtime/event/mutation callbacks.

Current implementation deliberately stops short of this phase-gated state
facade. Draw receives explicit `draw`, `data`, `actions`, and `services`
objects; mutation callbacks still receive `store` explicitly, and
hook/integration/overlay callbacks may close over the raw store returned by
module creation. Revisit `host.store` together with the draw/data API decision.

Typical use:

```lua
function ui.drawTab(host)
    host.widgets.checkbox("FeatureEnabled", {
        label = "Enabled",
    })

    local staged = host.session.read("FeatureEnabled")
end

host.hooks.wrap("SomeGameFunction", function(base, ...)
    if host.store.read("FeatureEnabled") then
        -- committed runtime behavior
    end
    return base(...)
end)
```

`host.store` should be an author-facing facade, not the raw managed store. The
facade can enforce phase and owner rules at method call time. This allows common
Lua patterns like:

```lua
local read = host.store.read
```

while still rejecting `read(...)` outside a Lib-owned runtime invocation window.

## Draw Facade

Draw is a Lib-owned invocation window.

The `ModuleHost` receives the Framework-facing call:

```lua
moduleHost.drawTab(imgui)
```

It should open the author host's draw phase, invoke the authored callback, and
always close the phase:

```lua
authorHost:_beginDraw(imgui)
local ok, result = pcall(drawTab, authorHost)
local closeOk, closeErr = pcall(authorHost._endDraw, authorHost)
```

During draw, these surfaces are available:

- `host.imgui`
- `host.widgets`
- `host.nav`
- `host.session`

After draw, those surfaces reject or become inert with clear phase errors.

This keeps the author API simple without pretending ImGui draw stack state is
globally valid.

## Hooks

Hooks are a strong candidate for host enclosure because it removes ownerless
ambient registration.

Destination:

```lua
host.hooks.wrap("GetEligibleLootNames", function(base, excludeLootNames)
    if not host.store.read("FeatureEnabled") then
        return base(excludeLootNames)
    end
    -- runtime behavior
end)
```

The author no longer calls `lib.hooks.*`. Ownership is structural because the
hook registrar is already bound to the module host.

Author hook declarations are staged on managed host state until activation.
The hook declaration backend should only build plain declaration records; it
should not keep a host-keyed weak registry of staged author declarations.

Store access should be open during hook dispatch, not during general module
declaration. Hook handlers may capture `host.store.read`; the facade should
validate phase when the captured function is called.

## Overlays

Overlay declaration moves from a callback-scoped registrar to a host-scoped
declaration namespace:

```lua
host.overlays.createLine("summary", spec)

host.overlays.onCommit(function(ctx, commit)
    ctx.setLine("summary", {
        label = "Enabled",
        value = tostring(ctx.read("FeatureEnabled")),
    })
    ctx.refresh("summary")
end)
```

Overlay projection callbacks may keep their projection context. That context is
already event-specific and intentionally narrower than the author host.

Author overlay declarations are staged on managed host state until activation.
The declaration backend should only build plain declaration records; the host
adapter translates `host.getHostId()` into the owner id consumed by retained
overlay internals.

The declaration namespace closes after activation. Projection callbacks run
later under Lib-owned overlay dispatch.

## Mutations

Mutations are lifecycle-owned and already have lower lingering side effects than
hooks or integration providers. Lib builds and applies plans during activation,
enable/disable, settings commit, reload, and rollback.

Destination:

```lua
host.mutation.patch(function(plan, host, store)
    if store.read("FeatureEnabled") then
        plan:set(SomeGameTable, "Enabled", true)
    end
end)
```

The callback keeps the explicit `(plan, host, store)` shape for now. Mutation
plan application and rollback remain internal lifecycle-host responsibilities.
Moving runtime reads to a phase-gated `host.store` facade is a separate design
choice that should be evaluated together with the draw/session shape.

## Integrations

Cache clarified the rule for host facades: bind the stable lifecycle
owner at the host boundary, but do not move backend ownership or unrelated
identity concepts into the host.

For integrations, keep these identities separate:

- lifecycle owner: the module host/plugin runtime identity that owns activation,
  rollback, refresh, and retirement
- provider id: the public cross-module provider identity returned to consumers
- integration id: the domain API name, such as
  `run-director.god-availability`

Do not collapse `providerId` into `pluginGuid` by accident. A default provider
id may be added for ergonomics, but it must be an explicit documented policy.
The host facade's first responsibility is lifecycle ownership, not redefining
public provider identity.

Provider registration should be host-owned:

```lua
host.integrations.register("run-director.god-availability", {
    providerId = "GodPool",
    api = {
        isActive = function()
            return host.isEnabled()
        end,
        isAvailable = function(godKey)
            return host.store.read(godKey) ~= false
        end,
    },
})
```

The host path does not use `ActiveHostInstallStack`-style ambient ownership
inference. `host.integrations.register(...)` records against the host directly
before activation. Provider registration is no longer exposed through the
global integration namespace.

Consumer invocation can be exposed on the host for author ergonomics and
future caller-aware diagnostics:

```lua
local ok = host.integrations.invoke("run-director.god-availability", "isAvailable", true, godKey)
```

This should remain a facade over the global integration registry, not
caller-aware RPC. Lib may know that host A invoked provider code owned by host
B for diagnostics, phase gating, and future policy, but that caller identity
should not be passed to provider methods by default.

Provider APIs should stay domain-shaped:

```lua
isAvailable = function(godKey)
    return host.store.read(godKey) ~= false
end
```

Do not turn integrations into caller-aware RPC unless a concrete use case needs
that larger contract.

Validation ownership should follow the cache lesson:

- `host.integrations.register(...)` validates the author-facing registration
  shape and binds lifecycle ownership
- `registry.lua` should trust normalized ids, provider ids, APIs, and
  owner ids/tokens once called internally
- `invoke(...)` validates `id` and `methodName` because invocation is an
  author-facing call boundary
- provider method failures stay under `integrations.provider_failed`

Do not expose direct public provider registration, invocation, `get`, or `list`
unless a concrete advanced use case survives the host-facade migration.

Provider APIs also need careful wrapping if strict store-phase enforcement is a
goal. `invoke(...)` is easy to phase-scope because Lib owns the call boundary;
direct provider-table access can bypass invocation wrapping.

## Cache

Cache has an author-host facade, but it is not a capability declaration like
hooks or overlays.

The cache subsystem owns stateless backends for namespaced runtime cache
domains. Cache values are not staged, hashed, profiled, or reset by Lib.

The backend is internal service code. The module-author surface is only the
host-bound facade; there is no global `lib.cache.*` author API.

The host facade receives the managed host, uses private host state only to
verify that the object is Lib-managed, then reads runtime ownership from
`host.getHostId()`. The host adapter translates that module runtime identity
into the `ownerId` passed to the backend. The backend only sees an owner key
used under the cache root. The facade then exposes concrete domains.

The active-run domain stores live mutable table buckets on `CurrentRun`:

```lua
local state = host.cache.currentRun.get("run", function()
    return {
        ForcedNPCPending = {},
    }
end)
```

Current-run surface:

```lua
host.cache.currentRun.get(key, factory)
host.cache.currentRun.peek(key)
host.cache.currentRun.clear(key)
```

This is intentionally more specific than `host.cache.get(...)`. It tells
authors that the bucket is tied to the active run, not a general memoization
table.

The persistent domain stores flat scalar values outside storage/session/hash
flows:

```lua
local ready = host.cache.persistent.read("RecordingReady", false)
host.cache.persistent.write("RecordingReady", true)
host.cache.persistent.clear("RecordingReady")
```

Persistent surface:

```lua
host.cache.persistent.read(key, default)
host.cache.persistent.write(key, value)
host.cache.persistent.clear(key)
host.cache.persistent.has(key)
```

Persistent values are limited to boolean, number, and string. Do not accept
tables here unless a real use case proves that flat scalar cache is too small;
complex persistent author state should be serialized explicitly by the module.

Future domains can be added when real call sites need them:

```lua
host.cache.currentRoom.get(key, factory)
host.cache.currentEncounter.get(key, factory)
```

Do not introduce stringly typed domains such as
`host.cache.get("CurrentRun", key, factory)` unless the runtime grows a real
domain registry. Concrete domains keep supported lifetimes grep-visible and
documentable.

## Error Style

Phase errors should name the violated surface and phase clearly:

```text
host.widgets.checkbox requires an active draw phase
host.imgui requires an active draw phase
host.hooks.wrap cannot be called after host activation
host.overlays.createLine cannot be called after host activation
host.store.read requires a runtime callback phase
host.session.read requires an active draw phase
```

These are author mistakes, not internal impossibilities. They should fail at the
author boundary with direct messages.

## Hot Reload

Hot reload should keep the existing replacement model:

1. module file reload creates a fresh author host
2. module code declares the complete current capability set
3. `host.activate()` creates a candidate lifecycle activation
4. Lib installs the new capability set or rolls back
5. omitted declarations are retired

Author declarations must be complete and repeatable. A reload should not rely on
mutating a previously activated author host.

## Migration Strategy

This is a destination design, not an immediate one-step migration.

Recommended migration path:

1. Add author-host declaration namespaces while keeping current callback options.
2. Route new namespaces through the existing stateless capability backends.
3. Add phase tracking and phase-gated store/session/draw facades.
4. Convert first-party modules to host declarations.
5. Update module-author docs to teach host-first authoring.
6. Keep legacy callback/global APIs temporarily.
7. Retire legacy author-facing global capability APIs after module conversion.

During migration, avoid making both models equally permanent. The destination is
host facade over stateless Lib backends.

## Non-Goals

- Do not make Lib capability modules stateful global services.
- Do not expose raw managed store/session objects directly through host.
- Do not make `host.read(...)` choose session or store by phase.
- Do not flatten all capability methods directly onto host.
- Do not turn `ModuleHost` into the author capability surface.
- Do not force integration consumer APIs into this design before their call
  sites are audited.
- Do not make current-run cache a stringly typed event cache.

## Design Summary

The target architecture is:

```text
Lib:
  stateless construction and backend capability implementation

ModuleHost:
  internal/framework-facing runtime and lifecycle owner

authorHost:
  module-facing bound capability facade

capability namespaces:
  host.hooks
  host.overlays
  host.integrations
  host.mutation
  host.widgets
  host.nav
  host.cache

state:
  host.session during draw
  host.store during sanctioned runtime/event/mutation callbacks
```

This aligns the module-author API with the lifecycle model the runtime already
uses, while keeping backend services stateless and testable.
