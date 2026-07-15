-- luacheck: no unused args
---@meta adamant-ModpackLib

---@class AdamantModpackLib
local lib = {}

---@alias AdamantModpackLib.Color number[]
---@alias AdamantModpackLib.ChoiceValue any
---@alias AdamantModpackLib.ChoiceDisplayValues table<any, string>
---@alias AdamantModpackLib.ChoiceVisibilityMap table<any, boolean>
---@alias AdamantModpackLib.ValueColorMap table<any, AdamantModpackLib.Color>
---@alias AdamantModpackLib.PackedSelectionMode "singleEnabled"|"singleDisabled"
---@alias AdamantModpackLib.MutationShape "patch"

---@class AdamantModpackLib.DropdownValueRange
---@field min? number First generated integer value. Defaults to 0.
---@field max? number Last generated integer value. Defaults to min.
---@field step? number Positive integer step between generated values. Defaults to 1.
---@field prepend? number|number[] Extra integer value(s) rendered before the generated range.
---@field append? number|number[] Extra integer value(s) rendered after the generated range.
---@field prefix? string Text prepended to generated range labels.
---@field suffix? string Text appended to generated range labels.

---@class AdamantModpackLib.StorageNode
---@field type "bool"|"int"|"string"|"packedInt"|"table"
---@field alias string Public alias used by runtime/UI data and widget APIs as the managed storage key.
---@field label? string UI label.
---@field tooltip? string UI tooltip.
---@field default? any Default value for this storage node.
---@field persist? boolean Whether the alias persists through config; defaults true.
---@field hash? boolean Whether the alias participates in hash/profile surfaces; defaults true.
---@field min? number Integer lower bound.
---@field max? number Integer upper bound.
---@field width? number Hash bit width for bounded `int`; required root bit width for `packedInt`.
---@field maxLen? number String max length for input widgets/hash normalization.
---@field bits? AdamantModpackLib.PackedBitNode[] Packed child bit aliases for `packedInt`.
---@field row? AdamantModpackLib.StorageSchema Row schema for `table` roots.
---@field minRows? integer Minimum row count for `table` roots.
---@field maxRows? integer Maximum row count for `table` roots.
---@field defaultRows? integer Default row count for `table` roots.

---@class AdamantModpackLib.PackedBitNode
---@field type "bool"|"int"
---@field alias string Public alias for a child bit field.
---@field label? string UI label.
---@field tooltip? string UI tooltip.
---@field default? any Default value for this bit field.
---@field offset number Bit offset inside the parent packed integer.
---@field width number Bit width inside the parent packed integer.
---@field min? number Integer lower bound.
---@field max? number Integer upper bound.

---@alias AdamantModpackLib.StorageSchema AdamantModpackLib.StorageNode[]

---Table handles are object handles; call methods with colon syntax (`rows:read(...)`).
---@class AdamantModpackLib.StorageTableReadOnly
---@field count fun(self: AdamantModpackLib.StorageTableReadOnly): integer
---@field get fun(self: AdamantModpackLib.StorageTableReadOnly, rowIndex: integer, alias: string): AdamantModpackLib.StorageFieldReadOnly
---@field read fun(self: AdamantModpackLib.StorageTableReadOnly, rowIndex: integer, alias: string): any
---@field snapshot fun(self: AdamantModpackLib.StorageTableReadOnly, rowIndex: integer): table?
---@field snapshots fun(self: AdamantModpackLib.StorageTableReadOnly): table[]

---Writable table handles are object handles; call methods with colon syntax (`rows:write(...)`).
---@class AdamantModpackLib.StorageTableStagedState: AdamantModpackLib.StorageTableReadOnly
---@field get fun(self: AdamantModpackLib.StorageTableStagedState, rowIndex: integer, alias: string): AdamantModpackLib.StorageField
---@field write fun(self: AdamantModpackLib.StorageTableStagedState, rowIndex: integer, alias: string, value: any): boolean
---@field reset fun(self: AdamantModpackLib.StorageTableStagedState, rowIndex: integer, alias: string): boolean
---@field append fun(self: AdamantModpackLib.StorageTableStagedState, rowValues?: table): boolean
---@field insert fun(self: AdamantModpackLib.StorageTableStagedState, rowIndex: integer, rowValues?: table): boolean
---@field remove fun(self: AdamantModpackLib.StorageTableStagedState, rowIndex: integer): boolean
---@field clear fun(self: AdamantModpackLib.StorageTableStagedState): boolean

---@class AdamantModpackLib.StorageFieldReadOnly
---@field read fun(self: AdamantModpackLib.StorageFieldReadOnly): any
---@field readAlias fun(
---    self: AdamantModpackLib.StorageFieldReadOnly,
---    alias: string
---): any Read another alias in this field's storage scope.
---@field schema fun(self: AdamantModpackLib.StorageFieldReadOnly): AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode
---@field alias fun(self: AdamantModpackLib.StorageFieldReadOnly): string
---@field controlId fun(self: AdamantModpackLib.StorageFieldReadOnly): string Draw/control identity from the current owner structure.

---@class AdamantModpackLib.StorageField: AdamantModpackLib.StorageFieldReadOnly
---@field write fun(self: AdamantModpackLib.StorageField, value: any): boolean?
---@field writeAlias fun(
---    self: AdamantModpackLib.StorageField,
---    alias: string,
---    value: any
---): boolean? Write another alias in this field's storage scope.
---@field reset fun(self: AdamantModpackLib.StorageField): boolean?

---@alias AdamantModpackLib.StoreDataRef AdamantModpackLib.StorageFieldReadOnly|AdamantModpackLib.StorageTableReadOnly
---@alias AdamantModpackLib.StatusDataRef AdamantModpackLib.StorageField|AdamantModpackLib.StorageTableStagedState
---@alias AdamantModpackLib.DrawStateRef AdamantModpackLib.StorageField|AdamantModpackLib.StorageTableStagedState
---@alias AdamantModpackLib.WidgetTarget AdamantModpackLib.StorageField
---@alias AdamantModpackLib.PackedChoiceOpts AdamantModpackLib.PackedDropdownOpts|AdamantModpackLib.PackedRadioOpts

---Internal trusted persistent state. Module authors access this through `runtime.data`.
---@class AdamantModpackLib.PersistentState
---@field get fun(alias: string): AdamantModpackLib.StoreDataRef? Return committed setting storage object.
---@field read fun(alias: string): any
---@field status AdamantModpackLib.StatusState
---@field table fun(alias: string): AdamantModpackLib.StorageTableReadOnly?
---@field getAliasSchema fun(alias: string): AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode|nil Read-only schema metadata.

---Committed runtime state facade. Reads are available wherever this facade is provided.
---@class AdamantModpackLib.Store
---@field get fun(alias: string): AdamantModpackLib.StoreDataRef? Return read-only committed setting storage object.
---@field cache AdamantModpackLib.StoreCache
---@field shared AdamantModpackLib.RuntimeSharedData
---@field read fun(alias: string, ...): any Read through `get(alias):read(...)`.

---@class AdamantModpackLib.RuntimeStatus
---@field get fun(alias: string): AdamantModpackLib.StatusDataRef? Return writable runtime-authored status object.
---@field read fun(alias: string, ...): any Read a declared status alias or table cell.
---@field write fun(alias: string, ...): boolean Write a declared status alias or table cell.
---@field reset fun(alias: string, ...): boolean Reset a declared status alias or table cell.

---@class AdamantModpackLib.StatusState: AdamantModpackLib.RuntimeStatus
---@field countResettable fun(opts?: AdamantModpackLib.ResetOpts): boolean, integer
---@field resetAll fun(opts?: AdamantModpackLib.ResetOpts): boolean, integer

---Internal trusted staged state. Module authors access this through `ui.data`.
---@class AdamantModpackLib.StagedState
---@field get fun(alias: string): AdamantModpackLib.DrawStateRef? Return a storage object for a staged alias.
---@field read fun(alias: string): any
---@field table fun(alias: string): AdamantModpackLib.StorageTableStagedState?
---@field field fun(alias: string): AdamantModpackLib.StorageField
---@field getAliasSchema fun(alias: string): AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode|nil Read-only schema metadata.
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)
---@field _flushToConfig fun()
---@field _hasConfigChanges fun(): boolean
---@field _reloadFromConfig fun(): AdamantModpackLib.ReloadReceipt
---@field _captureDirtyConfigSnapshot fun(): table[]
---@field _restoreConfigSnapshot fun(snapshot: table[]?)
---@field isDirty fun(): boolean
---@field auditMismatches fun(): string[]

---Staged UI state facade provided to draw callbacks.
---@class AdamantModpackLib.DrawState
---@field get fun(alias: string): AdamantModpackLib.DrawStateRef? Return a storage object for a staged alias.
---@field shared AdamantModpackLib.UiSharedData
---@field read fun(alias: string, ...): any Read through `get(alias):read(...)`.
---@field write fun(alias: string, ...): boolean? Write through `get(alias):write(...)`.

---@class AdamantModpackLib.UiStatus
---@field get fun(alias: string): AdamantModpackLib.StoreDataRef? Return read-only runtime-authored status object.
---@field read fun(alias: string, ...): any Read a declared status alias or table cell.

---@class AdamantModpackLib.StatusNode
---@field type "bool"|"int"|"string"|"packedInt"|"table"
---@field label? string UI label.
---@field tooltip? string UI tooltip.
---@field default? any Default value for this status node.
---@field persist boolean Whether the status survives config reloads.
---@field min? number Integer lower bound.
---@field max? number Integer upper bound.
---@field width? number Packed/hash bit width for bounded `int`; required root bit width for `packedInt`.
---@field maxLen? number String max length for normalization.
---@field bits? AdamantModpackLib.PackedBitNode[] Packed child bit aliases for `packedInt`.
---@field row? AdamantModpackLib.StorageSchema Row schema for `table` roots.
---@field minRows? integer Minimum row count for `table` roots.
---@field maxRows? integer Maximum row count for `table` roots.
---@field defaultRows? integer Default row count for `table` roots.

---@alias AdamantModpackLib.StatusDeclarationMap table<string, AdamantModpackLib.StatusNode>

---Draw callback action surface for staging one-shot UI intent.
---@class AdamantModpackLib.DrawActions
---@field get fun(actionKey: string): AdamantModpackLib.DrawActionRef
---@field trigger fun(actionKey: string, value?: any) Stage a declared action. Omitted value stages `true`.

---Draw callback action ref. Use colon syntax.
---@class AdamantModpackLib.DrawActionRef
---@field stage fun(self: AdamantModpackLib.DrawActionRef, value: any)
---@field read fun(self: AdamantModpackLib.DrawActionRef): any
---@field clear fun(self: AdamantModpackLib.DrawActionRef)
---@field has fun(self: AdamantModpackLib.DrawActionRef): boolean

---@class AdamantModpackLib.CommitActions
---@field get fun(actionKey: string): AdamantModpackLib.CommitActionRef
---@field hasAny fun(): boolean

---@class AdamantModpackLib.CommitActionRef
---@field read fun(self: AdamantModpackLib.CommitActionRef): any
---@field has fun(self: AdamantModpackLib.CommitActionRef): boolean

---@class AdamantModpackLib.CommitContext
---@field actions AdamantModpackLib.CommitActions
---@field hadConfigChanges fun(): boolean

---@alias AdamantModpackLib.ControlDrawCallback fun(
---    draw: AdamantModpackLib.DrawContext,
---    control: AdamantModpackLib.ControlRef,
---    instance: table,
---    ...: any
---): any

---@class AdamantModpackLib.ControlTemplate
---@field prepare? fun(instance: table): table
---@field storage? AdamantModpackLib.StorageSchema|fun(instance: table): AdamantModpackLib.StorageSchema
---@field createRuntime? fun(fields: table<string, AdamantModpackLib.StoreDataRef>, instance: table): AdamantModpackLib.ControlRef
---@field createUi? fun(fields: table<string, AdamantModpackLib.DrawStateRef>, instance: table): AdamantModpackLib.ControlRef
---@field draw? AdamantModpackLib.ControlDrawCallback
---@field views? table<string, AdamantModpackLib.ControlDrawCallback>

---@class AdamantModpackLib.ControlDeclaration
---@field template string

---@class AdamantModpackLib.ControlRef
---@field name fun(self: AdamantModpackLib.ControlRef): string
---@field kind fun(self: AdamantModpackLib.ControlRef): string
---@field read? fun(self: AdamantModpackLib.ControlRef, ...): any

---@class AdamantModpackLib.AuthorControls
---@field defineTemplates fun(templates: table<string, AdamantModpackLib.ControlTemplate>): nil
---@field define fun(instances: table<string, AdamantModpackLib.ControlDeclaration>): nil

---@class AdamantModpackLib.RuntimeControls
---@field get fun(name: string): AdamantModpackLib.ControlRef
---@field read fun(name: string, ...): any

---@class AdamantModpackLib.UiControls
---@field get fun(name: string): AdamantModpackLib.ControlRef
---@field read fun(name: string, ...): any
---@field reset fun(name: string): boolean, integer

---@class AdamantModpackLib.Host
---@field getOwnerId fun(): string
---@field getModuleId fun(): string
---@field getPackId fun(): string?
---@field getMeta fun(): AdamantModpackLib.ModuleMeta
---@field isEnabled fun(): boolean
---@field log fun(fmt: string, ...)
---@field logIf fun(fmt: string, ...)

---@class AdamantModpackLib.RuntimeContext
---@field data AdamantModpackLib.Store
---@field status AdamantModpackLib.RuntimeStatus
---@field controls AdamantModpackLib.RuntimeControls
---@field cache AdamantModpackLib.StoreCache?
---@field shared AdamantModpackLib.RuntimeSharedData?

---@class AdamantModpackLib.UiContext
---@field draw AdamantModpackLib.DrawContext
---@field data AdamantModpackLib.DrawState
---@field status AdamantModpackLib.UiStatus
---@field actions AdamantModpackLib.DrawActions
---@field controls AdamantModpackLib.UiControls
---@field shared AdamantModpackLib.UiSharedData?
---@field resetAll fun(opts?: AdamantModpackLib.ResetOpts): boolean Queue a full module reset for the current draw commit.

---@alias AdamantModpackLib.UiCallback fun(host: AdamantModpackLib.Host, ui: AdamantModpackLib.UiContext): nil
---@alias AdamantModpackLib.CommitCallback fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    commit: AdamantModpackLib.CommitContext
---): nil
---@alias AdamantModpackLib.ReloadReason "manual"|"frameworkSnapshot"|"hashReload"|"driftRepair"
---@alias AdamantModpackLib.ReloadCallback fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    reload: AdamantModpackLib.ReloadContext
---): nil

---@class AdamantModpackLib.ReloadContext
---@field reason fun(): AdamantModpackLib.ReloadReason
---@field hadCommittedChanges fun(): boolean
---@field hadSettingChanges fun(): boolean
---@field hadStatusChanges fun(): boolean

---@class AdamantModpackLib.ReloadReceipt
---@field hadCommittedChanges boolean
---@field hadSettingChanges boolean
---@field hadStatusChanges boolean
---@alias AdamantModpackLib.SharedListener fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    payload: any
---): nil
---@alias AdamantModpackLib.MutationPatchCallback fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    plan: AdamantModpackLib.MutationPlan
---): nil

---@class AdamantModpackLib.AuthorModule
---@field data { define: fun(storage: AdamantModpackLib.StorageSchema): nil }
---@field status { define: fun(status: AdamantModpackLib.StatusDeclarationMap): nil }
---@field actions { define: fun(actions: table<string, AdamantModpackLib.ModuleActionHandler>): nil }
---@field cache { define: fun(cache: AdamantModpackLib.CacheDeclarationMap): nil }
---@field controls AdamantModpackLib.AuthorControls
---@field ui { tab: fun(callback: AdamantModpackLib.UiCallback), quickContent: fun(callback: AdamantModpackLib.UiCallback) }
---@field onActivate fun(callback: fun(host: AdamantModpackLib.Host, runtime: AdamantModpackLib.RuntimeContext): nil): nil
---@field onCommit fun(callback: AdamantModpackLib.CommitCallback): nil
---@field onReload fun(callback: AdamantModpackLib.ReloadCallback): nil
---@field fallbackUi AuthorFallbackUi
---@field hooks AdamantModpackLib.ModuleHooks
---@field shared AdamantModpackLib.AuthorShared
---@field mutation { patch: fun(callback: AdamantModpackLib.MutationPatchCallback): nil }
---@field overlays AuthorOverlays
---@field activate fun(): boolean, string?
---@field getOwnerId fun(): string
---@field getModuleId fun(): string
---@field getPackId fun(): string?
---@field getMeta fun(): AdamantModpackLib.ModuleMeta
---@field isEnabled fun(): boolean
---@field log fun(fmt: string, ...)
---@field logIf fun(fmt: string, ...)

---@class AdamantModpackLib.AuthorFallbackUi
---@field attachGuiOnce fun(register: fun(ui: AdamantModpackLib.FallbackUiBridge)): boolean

---@alias AdamantModpackLib.HookWrapCallback fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    base: function,
---    ...: any
---): any
---@alias AdamantModpackLib.HookCallback fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    ...: any
---): any
---Nested `context.wrap(...)` handlers receive the raw wrapped path signature:
---the base function followed by the wrapped path's normal arguments. They do
---not receive host/runtime; close over those from the outer context callback.
---@alias AdamantModpackLib.ContextHookWrapCallback fun(base: function, ...: any): any
---@class AdamantModpackLib.HookContext
---@field wrap fun(path: string, handler: AdamantModpackLib.ContextHookWrapCallback)
---@alias AdamantModpackLib.HookContextCallback fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    context: AdamantModpackLib.HookContext,
---    ...: any
---): any

---@class AdamantModpackLib.AuthorHooks
---@field wrap fun(path: string, keyOrHandler: string|AdamantModpackLib.HookWrapCallback,
---    maybeHandler?: AdamantModpackLib.HookWrapCallback)
---@field override fun(path: string, keyOrCb: string|AdamantModpackLib.HookCallback,
---    maybeCallback?: AdamantModpackLib.HookCallback)
---@field contextWrap fun(path: string, keyOrContext: string|AdamantModpackLib.HookContextCallback,
---    maybeContext?: AdamantModpackLib.HookContextCallback)

---@class AdamantModpackLib.ModuleHooks
---@field wrap fun(path: string, keyOrHandler: string|AdamantModpackLib.HookWrapCallback,
---    maybeHandler?: AdamantModpackLib.HookWrapCallback)
---@field override fun(path: string, keyOrCb: string|AdamantModpackLib.HookCallback,
---    maybeCallback?: AdamantModpackLib.HookCallback)
---@field contextWrap fun(path: string, keyOrContext: string|AdamantModpackLib.HookContextCallback,
---    maybeContext?: AdamantModpackLib.HookContextCallback)

---@class AdamantModpackLib.AuthorShared
---@field data AdamantModpackLib.AuthorSharedData
---@field listen fun(id: string, eventName: string, callback: AdamantModpackLib.SharedListener): table

---@class AdamantModpackLib.AuthorSharedData
---@field owner fun(name: string, opts: AdamantModpackLib.SharedDataOwnerDeclaration): boolean
---@field reader fun(name: string, opts: AdamantModpackLib.SharedDataReaderDeclaration): boolean

---@class AdamantModpackLib.SharedDataOwnerDeclaration
---@field id string
---@field default? boolean|number|string|table

---@class AdamantModpackLib.SharedDataReaderDeclaration
---@field id string
---@field fallback? boolean|number|string|table

---@class AdamantModpackLib.AuthorMutation
---@field patch fun(callback: fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    plan: AdamantModpackLib.MutationPlan
---))

---@class AdamantModpackLib.CacheDeclarationCurrentRun
---@field domain "currentRun"
---@field key string
---@field factory? fun(): table

---@alias AdamantModpackLib.CacheDeclaration AdamantModpackLib.CacheDeclarationCurrentRun
---@alias AdamantModpackLib.CacheDeclarationMap table<string, AdamantModpackLib.CacheDeclaration>

---@class AdamantModpackLib.StoreCache
---@field currentRun AdamantModpackLib.StoreCurrentRunCache

---@class AdamantModpackLib.StoreCurrentRunCache
---@field get fun(name: string): table?
---@field clear fun(name: string): boolean

---@class AdamantModpackLib.SharedData
---@field read fun(name: string): boolean|number|string|table?
---@field set fun(name: string, value: boolean|number|string|table): boolean
---@field clear fun(name: string): boolean

---@class AdamantModpackLib.RuntimeSharedData: AdamantModpackLib.SharedData
---@field emit fun(
---    id: string,
---    eventName: string,
---    payload?: any
---): boolean, integer Runtime emits synchronously and returns delivered listener count.

---@class AdamantModpackLib.UiSharedData: AdamantModpackLib.SharedData
---@field emit fun(id: string, eventName: string, payload?: any): boolean Stages delivery for commit and does not return a listener count.

---@class AdamantModpackLib.ModuleDefinition
---@field modpack? string Coordinator pack id for coordinated modules.
---@field id string Stable module id within the pack.
---@field name string Display name.
---@field shortName? string Short UI label.
---@field tooltip? string UI tooltip.
---@field storage? AdamantModpackLib.StorageSchema Module storage schema.
---@field cache? AdamantModpackLib.CacheDeclarationMap Managed runtime cache declarations.
---@field actions? table<string, AdamantModpackLib.ModuleActionHandler> Module action handlers keyed by action id.

---@alias AdamantModpackLib.ModuleActionHandler fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    value: any
---)
---@alias AdamantModpackLib.DrawActionHandler AdamantModpackLib.ModuleActionHandler

---@class AdamantModpackLib.PreparedDefinition: AdamantModpackLib.ModuleDefinition

---@class AdamantModpackLib.MutationBundle
---@field patchMutation? fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    plan: AdamantModpackLib.MutationPlan
---)

---@class AdamantModpackLib.ModuleCreateOpts
---@field pluginGuid string Plugin guid captured at module file load time.
---@field modpack? string Module pack id used by Lib modpack grouping.
---@field id string Stable module id.
---@field name string Display name.
---@field shortName? string Short display name.
---@field tooltip? string UI tooltip.

---Immediate UI surface provided to draw callbacks; `imgui` is the raw environment ImGui table.
---@class AdamantModpackLib.DrawContext
---@field imgui table Raw ImGui backend table for custom layout and controls.
---@field widgets AdamantModpackLib.DrawWidgetsApi
---@field nav AdamantModpackLib.DrawNavApi
---@field control fun(control: AdamantModpackLib.ControlRef, viewName?: string, ...): any Render a control template view.

---@class AdamantModpackLib.ManagedModule
---@field getOwnerId fun(): string
---@field getModuleId fun(): string
---@field getPackId fun(): string?
---@field getMeta fun(): AdamantModpackLib.ModuleMeta
---@field affectsRunData fun(): boolean
---@field getStorage fun(): AdamantModpackLib.StorageSchema?
---@field read fun(alias: string): any
---@field writeAndFlush fun(alias: string, value: any): boolean
---@field stage fun(alias: string, value: any): boolean
---@field flush fun(): boolean
---@field reloadFromConfig fun(reason?: AdamantModpackLib.ReloadReason): AdamantModpackLib.ReloadContext
---@field resync fun(): string[], AdamantModpackLib.ReloadContext?
---@field resetAll fun(opts?: AdamantModpackLib.ResetOpts): boolean, integer
---@field commitIfDirty fun(): boolean, string?, boolean
---@field isEnabled fun(): boolean
---@field setEnabled fun(enabled: boolean): boolean, string?
---@field setDebugMode fun(enabled: boolean)
---@field suspendForPackDisable fun(): boolean, string?, table?
---@field ensureSuspendedForPackDisable fun(): boolean, string?, table?
---@field restoreForPackEnable fun(): boolean, string?, table?
---@field rollbackPackTransition fun(receipt: table?): boolean, string?
---@field restorePackTransitionState fun(receipt: table?): boolean, string?
---@field applyMutation fun(): boolean, string?
---@field revertMutation fun(): boolean, string?
---@field activate fun(): boolean, string?
---@field drawTab fun()
---@field drawQuickContent? fun()

---@class AdamantModpackLib.ModuleMeta
---@field name? string
---@field shortName? string
---@field tooltip? string

---@class AdamantModpackLib.ResetOpts
---@field exclude? table<string, boolean> Root aliases to skip.

---@class AdamantModpackLib.FallbackUiBridge
---@field renderWindow fun()
---@field addMenuBar fun()
---@field handleGuiClosed fun()

---@class AdamantModpackLib.CoordinatorConfig
---@field ModEnabled boolean

---@class AdamantModpackLib.ModpackConfig
---@field ModEnabled boolean Whether the coordinated modpack is enabled.
---@field DebugMode boolean Whether debug warnings should be visible.
---@field Profiles AdamantModpackLib.ModpackProfile[]

---@class AdamantModpackLib.ModpackProfile
---@field Name string
---@field Hash string
---@field Tooltip string

---@class AdamantModpackLib.ModpackOpts
---@field moduleOrder? string[] Ordered module ids to pin first in the sidebar.
---@field drawPackQuickContent? fun(ctx: AdamantModpackLib.ModpackQuickContentContext) Coordinator-owned Quick Setup renderer.
---@field hideHashMarker? boolean Suppress the HUD hash marker while keeping the coordinator UI active.

---@class AdamantModpackLib.ModpackThemeColors
---@field text AdamantModpackLib.Color
---@field textDisabled AdamantModpackLib.Color
---@field info AdamantModpackLib.Color
---@field warning AdamantModpackLib.Color
---@field success AdamantModpackLib.Color
---@field error AdamantModpackLib.Color
---@field mixed AdamantModpackLib.Color

---@class AdamantModpackLib.ModpackTheme
---@field colors AdamantModpackLib.ModpackThemeColors
---@field ImGuiTreeNodeFlags table
---@field PushTheme fun()
---@field PopTheme fun()

---@class AdamantModpackLib.ModpackQuickContentContext
---@field ui table ImGui API table.
---@field colors AdamantModpackLib.ModpackThemeColors
---@field theme AdamantModpackLib.ModpackTheme
---@field getModulesStatus fun(moduleIds: string[]): string, AdamantModpackLib.Color, boolean
---@field setModulesEnabled fun(moduleIds: string[], enabled: boolean): boolean, string?

---@class AdamantModpackLib.ModpackRuntime
---@field moduleRegistry table Opaque modpack module registry runtime.
---@field configHash table Opaque modpack config-hash runtime.
---@field hud table Opaque modpack HUD runtime.
---@field ui AdamantModpackLib.ModpackUiRuntime Opaque modpack UI runtime.

---@class AdamantModpackLib.ModpackUiRuntime
---@field renderWindow fun()
---@field addMenuBar fun()
---@field flushPending fun()
---@field handleGuiClosed fun()
---@field dispose fun()

---@class AdamantModpackLib.ModpackGuiCallbacks
---@field render fun() Main modpack window renderer for `rom.gui.add_imgui(...)`.
---@field alwaysDraw fun() Always-draw callback for `rom.gui.add_always_draw_imgui(...)`.
---@field menuBar fun() Menu-bar callback for `rom.gui.add_to_menu_bar(...)`.

---@alias AdamantModpackLib.RegisterCoordinatorFn fun(
---  packId: string,
---  displayName: string,
---  config: AdamantModpackLib.ModpackConfig?,
---  rebuildCallback?: fun(reason: table): boolean
---): boolean

---@alias AdamantModpackLib.CreatePackFn fun(
---  packId: string,
---  config: AdamantModpackLib.ModpackConfig,
---  numProfiles: integer,
---  defaultProfiles: table,
---  opts?: AdamantModpackLib.ModpackOpts
---): boolean, AdamantModpackLib.ModpackRuntime?, string?

---@class AdamantModpackLib.ModpackApi
---@field registerCoordinator AdamantModpackLib.RegisterCoordinatorFn
---@field createPack AdamantModpackLib.CreatePackFn
---@field createGuiCallbacks fun(packId: string): AdamantModpackLib.ModpackGuiCallbacks

---@class AdamantModpackLib.CoordinatorRuntime
---@field register fun(packId: string, displayName: string?, config: AdamantModpackLib.CoordinatorConfig?)
---@field registerRebuild fun(packId: string, callback: fun(reason: table): boolean?)
---@field isRegistered fun(packId: string): boolean
---@field getDisplayName fun(packId: string): string?

---@class AdamantModpackLib.MutationInfo
---@field hasPatch boolean

---@alias AdamantModpackLib.MutationPlanFn fun(self: AdamantModpackLib.MutationPlan, ...: any): AdamantModpackLib.MutationPlan

---@class AdamantModpackLib.MutationPlan
---@field set AdamantModpackLib.MutationPlanFn
---@field setMany AdamantModpackLib.MutationPlanFn
---@field transform AdamantModpackLib.MutationPlanFn
---@field append AdamantModpackLib.MutationPlanFn
---@field appendUnique AdamantModpackLib.MutationPlanFn
---@field removeElement AdamantModpackLib.MutationPlanFn
---@field setElement AdamantModpackLib.MutationPlanFn

---@class AdamantModpackLib.NavTab
---@field key string|number
---@field label? string
---@field group? string
---@field color? AdamantModpackLib.Color

---@class AdamantModpackLib.VerticalTabsOpts
---@field id? string|number
---@field navWidth? number
---@field height? number
---@field tabs? AdamantModpackLib.NavTab[]
---@field activeKey? string|number

---@class AdamantModpackLib.TextOpts
---@field color? AdamantModpackLib.Color
---@field tooltip? string
---@field alignToFramePadding? boolean

---@class AdamantModpackLib.ButtonOpts
---@field id? string|number
---@field tooltip? string
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when clicked.
---@field value? any Staged action payload.

---@class AdamantModpackLib.ConfirmButtonOpts
---@field tooltip? string
---@field confirmLabel? string
---@field cancelLabel? string
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when confirmed.
---@field value? any Staged action payload.

---@class AdamantModpackLib.InputTextOpts
---@field id? string|number
---@field label? string
---@field tooltip? string
---@field maxLen? number
---@field labelWidth? number
---@field controlWidth? number
---@field controlGap? number
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when edited.
---@field value? any Staged action payload. Defaults to the edited text.

---@class AdamantModpackLib.DropdownOpts
---@field id? string|number
---@field label? string
---@field tooltip? string
---@field values? AdamantModpackLib.ChoiceValue[]
---@field valueRange? AdamantModpackLib.DropdownValueRange Integer choices generated when `values` is absent.
---@field displayValues? AdamantModpackLib.ChoiceDisplayValues
---@field valueColors? AdamantModpackLib.ValueColorMap
---@field visibleValues? AdamantModpackLib.ChoiceVisibilityMap
---@field labelWidth? number
---@field controlWidth? number
---@field controlGap? number
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when selection changes.
---@field value? any Staged action payload. Defaults to the selected value.

---@class AdamantModpackLib.PackedDropdownOpts
---@field id? string|number
---@field label? string
---@field tooltip? string
---@field labelWidth? number
---@field controlWidth? number
---@field controlGap? number
---@field displayValues? AdamantModpackLib.ChoiceDisplayValues
---@field valueColors? table<string, AdamantModpackLib.Color>
---@field noneLabel? string
---@field multipleLabel? string
---@field selectionMode? AdamantModpackLib.PackedSelectionMode
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when selection changes.
---@field value? any Staged action payload. Defaults to selected child alias or false for none.

---@class AdamantModpackLib.RadioOpts
---@field label? string
---@field values? AdamantModpackLib.ChoiceValue[]
---@field displayValues? AdamantModpackLib.ChoiceDisplayValues
---@field valueColors? AdamantModpackLib.ValueColorMap
---@field visibleValues? AdamantModpackLib.ChoiceVisibilityMap
---@field optionsPerLine? number
---@field optionGap? number
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when selection changes.
---@field value? any Staged action payload. Defaults to the selected value.

---@class AdamantModpackLib.PackedRadioOpts
---@field label? string
---@field displayValues? AdamantModpackLib.ChoiceDisplayValues
---@field valueColors? table<string, AdamantModpackLib.Color>
---@field noneLabel? string
---@field selectionMode? AdamantModpackLib.PackedSelectionMode
---@field optionsPerLine? number
---@field optionGap? number
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when selection changes.
---@field value? any Staged action payload. Defaults to selected child alias or false for none.

---@class AdamantModpackLib.StepperOpts
---@field id? string|number
---@field label? string
---@field default? number
---@field min? number
---@field max? number
---@field step? number
---@field displayValues? table<number, string>
---@field valueWidth? number
---@field buttonSpacing? number
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when value changes.
---@field value? any Staged action payload. Defaults to the edited number.

---@class AdamantModpackLib.SteppedRangeOpts: AdamantModpackLib.StepperOpts
---@field defaultMax? number
---@field rangeGap? number

---@class AdamantModpackLib.CheckboxOpts
---@field label? string
---@field tooltip? string
---@field color? AdamantModpackLib.Color
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when toggled.
---@field value? any Staged action payload. Defaults to the edited boolean.

---@class AdamantModpackLib.PackedCheckboxListOpts
---@field filterText? string
---@field filterMode? "all"|"checked"|"unchecked"
---@field valueColors? table<string, AdamantModpackLib.Color>
---@field slotCount? number
---@field optionsPerLine? number
---@field optionGap? number
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when a child toggles.
---@field value? any Staged action payload. Defaults to `{ alias = childAlias, value = editedBoolean }`.

---@alias AdamantModpackLib.RetainedOverlayVisibleCallback fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext
---): boolean
---@alias AdamantModpackLib.SystemRetainedOverlayVisibleCallback fun(): boolean
---@alias AdamantModpackLib.RetainedOverlayVisible
---| boolean
---| AdamantModpackLib.RetainedOverlayVisibleCallback
---| AdamantModpackLib.SystemRetainedOverlayVisibleCallback

---@alias AdamantModpackLib.RetainedOverlayRegion
---| "middleRightStack"
---| "centerLowerStack"

---@class AdamantModpackLib.RetainedOverlayColumn
---@field key? string Stable column key used by retained values.
---@field componentName? string Explicit retained HUD component name for this column.
---@field minWidth? number Reserved layout width used to keep following columns aligned.
---@field justify? "Left"|"Center"|"Right" Column text justification.
---@field visible? AdamantModpackLib.RetainedOverlayVisible
---@field textArgs? table Text style overrides.

---@class AdamantModpackLib.RetainedLineSpec
---@field componentName? string Base retained HUD component name.
---@field region? AdamantModpackLib.RetainedOverlayRegion Stack region name. Defaults to `middleRightStack`.
---@field order? integer Sort key within the region.
---@field columnGap? number Reserved space between columns.
---@field columns? AdamantModpackLib.RetainedOverlayColumn[] Ordered columns, declared left-to-right.
---@field visible? AdamantModpackLib.RetainedOverlayVisible
---@field minWidth? number Width for one-column convenience lines.
---@field justify? "Left"|"Center"|"Right" Justification for one-column convenience lines.
---@field textArgs? table Text style overrides for one-column convenience lines.

---@class AdamantModpackLib.RetainedTableSpec
---@field componentName? string Base retained HUD component name.
---@field region? AdamantModpackLib.RetainedOverlayRegion Stack region name. Defaults to `middleRightStack`.
---@field order? integer Sort key for the first row within the region.
---@field maxRows integer Maximum retained rows to allocate.
---@field columnGap? number Reserved space between columns.
---@field columns AdamantModpackLib.RetainedOverlayColumn[] Ordered columns, declared left-to-right.
---@field visible? AdamantModpackLib.RetainedOverlayVisible

---@class AdamantModpackLib.RetainedOverlayProjection
---@field setLine fun(name: string, values: table|string): boolean
---@field setTable fun(name: string, rows: table[]): boolean
---@field setCell fun(tableName: string, rowKey: any, columnKey: string, value: any): boolean
---@field refresh fun(name: string): boolean
---@field refreshOwned fun(): boolean

---@class AdamantModpackLib.SystemRetainedOverlayProjection: AdamantModpackLib.RetainedOverlayProjection
---@field refreshRegion fun(region: AdamantModpackLib.RetainedOverlayRegion)
---@field refreshAll fun()

---@class AdamantModpackLib.OverlayHookEvent
---@field path string
---@field args table
---@field result any
---@field results table

---@alias AdamantModpackLib.OverlayCommitCallback fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    overlay: AdamantModpackLib.RetainedOverlayProjection,
---    commit: AdamantModpackLib.CommitContext
---)
---@alias AdamantModpackLib.OverlayIntervalCallback fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    overlay: AdamantModpackLib.RetainedOverlayProjection,
---    event: table
---)
---@alias AdamantModpackLib.OverlayIntervalWhenCallback fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    event: table
---): boolean
---@alias AdamantModpackLib.SystemOverlayIntervalWhenCallback fun(event: table): boolean
---@class AdamantModpackLib.OverlayIntervalOpts
---@field when? AdamantModpackLib.OverlayIntervalWhenCallback|AdamantModpackLib.SystemOverlayIntervalWhenCallback
---@alias AdamantModpackLib.OverlayAfterHookCallback fun(
---    host: AdamantModpackLib.Host,
---    runtime: AdamantModpackLib.RuntimeContext,
---    overlay: AdamantModpackLib.RetainedOverlayProjection,
---    event: AdamantModpackLib.OverlayHookEvent
---)
---@alias AdamantModpackLib.SystemOverlayCommitCallback fun(
---    overlay: AdamantModpackLib.SystemRetainedOverlayProjection,
---    commit: AdamantModpackLib.CommitContext
---)

---@class AdamantModpackLib.RetainedOverlayRegistrar
---@field order table<string, integer> Shared overlay order bands.
---@field createLine fun(name: string, spec: AdamantModpackLib.RetainedLineSpec)
---@field createTable fun(name: string, spec: AdamantModpackLib.RetainedTableSpec)
---@field onCommit fun(callback: AdamantModpackLib.OverlayCommitCallback)
---@field onInterval fun(
---    name: string,
---    seconds: number,
---    callback: AdamantModpackLib.OverlayIntervalCallback,
---    opts?: AdamantModpackLib.OverlayIntervalOpts
---)
---@field afterHook fun(
---    path: string,
---    callback: AdamantModpackLib.OverlayAfterHookCallback
---)

---@class AdamantModpackLib.SystemOverlayRegistrar
---@field createLine fun(name: string, spec: AdamantModpackLib.RetainedLineSpec)
---@field onCommit fun(callback: AdamantModpackLib.SystemOverlayCommitCallback)

---@class AdamantModpackLib.UiSuppressionToken
---@field release fun()

---Widget helpers. Call from `drawTab(...)` or `drawQuickContent(...)`.
---@class AdamantModpackLib.DrawWidgetsApi
---@field separator fun()
---@field text fun(text: any, opts?: AdamantModpackLib.TextOpts)
---@field button fun(label: any, opts?: AdamantModpackLib.ButtonOpts): boolean
---@field confirmButton fun(id: string|number, label: any, opts?: AdamantModpackLib.ConfirmButtonOpts): boolean
---@field inputText fun(target: AdamantModpackLib.WidgetTarget, opts?: AdamantModpackLib.InputTextOpts): boolean
---@field dropdown fun(target: AdamantModpackLib.WidgetTarget, opts?: AdamantModpackLib.DropdownOpts): boolean
---@field packedDropdown fun(target: AdamantModpackLib.WidgetTarget, opts?: AdamantModpackLib.PackedDropdownOpts): boolean
---@field getPackedChoiceAlias fun(target: AdamantModpackLib.WidgetTarget, opts?: AdamantModpackLib.PackedChoiceOpts): string?
---@field radio fun(target: AdamantModpackLib.WidgetTarget, opts?: AdamantModpackLib.RadioOpts): boolean
---@field packedRadio fun(target: AdamantModpackLib.WidgetTarget, opts?: AdamantModpackLib.PackedRadioOpts): boolean
---@field stepper fun(target: AdamantModpackLib.WidgetTarget, opts?: AdamantModpackLib.StepperOpts): boolean
---@field steppedRange fun(
---    minTarget: AdamantModpackLib.WidgetTarget,
---    maxTarget: AdamantModpackLib.WidgetTarget,
---    opts?: AdamantModpackLib.SteppedRangeOpts
---): boolean
---@field checkbox fun(target: AdamantModpackLib.WidgetTarget, opts?: AdamantModpackLib.CheckboxOpts): boolean
---@field packedCheckboxList fun(target: AdamantModpackLib.WidgetTarget, opts?: AdamantModpackLib.PackedCheckboxListOpts): boolean

---Navigation helpers. Call from `drawTab(...)` or `drawQuickContent(...)`.
---@class AdamantModpackLib.DrawNavApi
---@field verticalTabs fun(opts?: AdamantModpackLib.VerticalTabsOpts): string|number?

---Internal constructed module state bundle.
---@class AdamantModpackLib.ModuleState
---@field persistentState AdamantModpackLib.PersistentState
---@field stagedState AdamantModpackLib.StagedState

---@type AdamantModpackLib.ModpackApi
lib.modpack = {}

---@param opts AdamantModpackLib.ModuleCreateOpts
---@return AdamantModpackLib.AuthorModule? module
---@return string? err
function lib.createModule(opts)
end

return lib
