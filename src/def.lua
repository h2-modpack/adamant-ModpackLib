-- luacheck: no unused args
---@meta adamant-ModpackLib

---@class AdamantModpackLib
local lib = {}

---@alias AdamantModpackLib.Color number[]
---@alias AdamantModpackLib.ChoiceValue any
---@alias AdamantModpackLib.ChoiceDisplayValues table<any, string>
---@alias AdamantModpackLib.ValueColorMap table<any, AdamantModpackLib.Color>
---@alias AdamantModpackLib.PackedSelectionMode "singleEnabled"|"singleDisabled"
---@alias AdamantModpackLib.MutationShape "patch"

---@class AdamantModpackLib.HashGroup
---@field keyPrefix string Hash group family prefix.
---@field items (string|string[])[] Ordered aliases or alias bundles to pack together.

---@alias AdamantModpackLib.HashGroupPlan AdamantModpackLib.HashGroup[]

---@class AdamantModpackLib.StorageNode
---@field type "bool"|"int"|"string"|"packedInt"|"table"
---@field alias string Public alias used by store/state/widget APIs and as the persisted backing key.
---@field label? string UI label.
---@field tooltip? string UI tooltip.
---@field default? any Default value for this storage node.
---@field persist? boolean Whether the alias persists through config; defaults true.
---@field hash? boolean Whether the alias participates in hash/profile surfaces; defaults true.
---@field min? number Integer lower bound.
---@field max? number Integer upper bound.
---@field width? number Packed/hash bit width for integer-like nodes.
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
---@alias AdamantModpackLib.DrawStateRef AdamantModpackLib.StorageField|AdamantModpackLib.StorageTableStagedState
---@alias AdamantModpackLib.WidgetTarget AdamantModpackLib.StorageField
---@alias AdamantModpackLib.PackedChoiceOpts AdamantModpackLib.PackedDropdownOpts|AdamantModpackLib.PackedRadioOpts

---Internal trusted persistent state. Module authors receive `Store`.
---@class AdamantModpackLib.PersistentState
---@field get fun(alias: string): AdamantModpackLib.StoreDataRef? Return a storage object for a persisted alias.
---@field read fun(alias: string): any
---@field table fun(alias: string): AdamantModpackLib.StorageTableReadOnly?
---@field getAliasSchema fun(alias: string): AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode|nil Read-only schema metadata.

---Committed runtime state facade. Store methods are valid outside draw callbacks and reject while any module draw callback is running.
---@class AdamantModpackLib.Store
---@field get fun(alias: string): AdamantModpackLib.StoreDataRef? Return a read-only storage object for a persisted alias.
---@field read fun(alias: string, ...): any Read through `get(alias):read(...)`.

---Internal trusted staged state. Module authors receive `DrawState` during draw callbacks.
---@class AdamantModpackLib.StagedState
---@field view table<string, any>
---@field get fun(alias: string): AdamantModpackLib.DrawStateRef? Return a storage object for a staged alias.
---@field read fun(alias: string): any
---@field table fun(alias: string): AdamantModpackLib.StorageTableStagedState?
---@field field fun(alias: string): AdamantModpackLib.StorageField
---@field getAliasSchema fun(alias: string): AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode|nil Read-only schema metadata.
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)
---@field _flushToConfig fun()
---@field _hasConfigChanges fun(): boolean
---@field _reloadFromConfig fun()
---@field _captureDirtyConfigSnapshot fun(): table[]
---@field _restoreConfigSnapshot fun(snapshot: table[]?)
---@field isDirty fun(): boolean
---@field auditMismatches fun(): string[]

---Draw-phase staged UI state facade. Methods and returned refs are valid only during draw callbacks.
---@class AdamantModpackLib.DrawState
---@field get fun(alias: string): AdamantModpackLib.DrawStateRef? Return a storage object for a staged alias.
---@field read fun(alias: string, ...): any Read through `get(alias):read(...)`.
---@field write fun(alias: string, ...): boolean? Write through `get(alias):write(...)`.
---@field resetAll fun(opts?: AdamantModpackLib.ResetOpts): boolean, integer

---Draw-phase transient action surface. Methods and returned refs are valid only during draw callbacks.
---@class AdamantModpackLib.DrawActions
---@field get fun(actionKey: string): AdamantModpackLib.DrawActionRef
---@field hasAny fun(): boolean

---Draw-phase action ref. Use colon syntax; methods are valid only during draw callbacks.
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

---Module-facing host facade. Declare host-owned capabilities before activation; declaration namespaces reject after activation.
---@class AdamantModpackLib.AuthorHost
---Activates module hooks, integrations, live-host registration, and initial runtime sync.
---Call once after construction.
---@field activate fun(): boolean, string? Safely activates the host and returns an error instead of throwing.
---@field isEnabled fun(): boolean
---@field getHostId fun(): string
---@field getModuleId fun(): string
---@field getPackId fun(): string?
---@field getMeta fun(): AdamantModpackLib.ModuleMeta
---@field log fun(fmt: string, ...) Print a module-scoped log line.
---@field logIf fun(fmt: string, ...) Print a module-scoped log line when DebugMode is enabled.
---@field fallbackUi AdamantModpackLib.AuthorFallbackUi
---@field cache AdamantModpackLib.AuthorCache
---@field hooks AdamantModpackLib.AuthorHooks
---@field integrations AdamantModpackLib.AuthorIntegrations
---@field mutation AdamantModpackLib.AuthorMutation
---@field overlays AdamantModpackLib.RetainedOverlayRegistrar

---Draw-phase service surface. Methods are valid only during draw callbacks.
---@class AdamantModpackLib.DrawServices
---@field cache AdamantModpackLib.DrawServicesCache
---@field log fun(fmt: string, ...) Print a module-scoped log line from draw code.
---@field logIf fun(fmt: string, ...) Print a module-scoped log line from draw code when DebugMode is enabled.
---@field pollIntegration fun(id: string, methodName: string, fallback: any, ...): any, string? Poll a registered integration method.

---@class AdamantModpackLib.DrawServicesCache
---@field shared AdamantModpackLib.DrawServicesSharedCache

---@class AdamantModpackLib.DrawServicesSharedCache
---@field read fun(id: string, fallback: any): any Read an owner-published shared cache projection.
---@field write fun(id: string, value: any): boolean Write an owned shared cache projection from draw code.
---@field clear fun(id: string): boolean Clear an owned shared cache projection from draw code.

---@class AdamantModpackLib.FrameworkRuntime
---@field diagnostics AdamantModpackLib.FrameworkDiagnosticsRuntime
---@field coordinator AdamantModpackLib.FrameworkCoordinatorRuntime
---@field hashing AdamantModpackLib.FrameworkHashingApi
---@field modules AdamantModpackLib.FrameworkModulesRuntime
---@field overlays AdamantModpackLib.FrameworkOverlaysRuntime
---@field ui AdamantModpackLib.FrameworkUiRuntime

---@class AdamantModpackLib.FrameworkDiagnosticsRuntime
---@field isLibDebugEnabled fun(): boolean
---@field setLibDebugEnabled fun(enabled: boolean)

---@class AdamantModpackLib.FrameworkCoordinatorRuntime
---@field register fun(packId: string, config: table?)
---@field registerRebuild fun(packId: string, callback: fun(reason: table)|nil)
---@field isRegistered fun(packId: string?): boolean

---@class AdamantModpackLib.FrameworkModulesRuntime
---@field getLiveHost fun(pluginGuid: string?): AdamantModpackLib.ModuleHost?

---@class AdamantModpackLib.FrameworkOverlaysRuntime
---@field order table<string, integer> Shared overlay order bands.
---@field define fun(packId: string, name: string, register: fun(overlays: AdamantModpackLib.SystemOverlayRegistrar)): boolean

---@alias AdamantModpackLib.StorageAliasMap table<string, AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode>

---@class AdamantModpackLib.FrameworkHashingApi
---@field getRoots fun(storage: AdamantModpackLib.StorageSchema): AdamantModpackLib.StorageNode[]
---@field getAliases fun(storage: AdamantModpackLib.StorageSchema): AdamantModpackLib.StorageAliasMap
---@field valuesEqual fun(node: AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode?, a: any, b: any): boolean
---@field getPackWidth fun(node: AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode): number?
---@field toHash fun(node: AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode, value: any): string?
---@field fromHash fun(node: AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode, str: string): any
---@field isHashTokenValid fun(node: AdamantModpackLib.StorageNode|AdamantModpackLib.PackedBitNode, str: string?): boolean
---@field readPackedBits fun(packed: number?, offset: number?, width: number?): number
---@field writePackedBits fun(packed: number?, offset: number?, width: number?, value: number?): number

---@class AdamantModpackLib.FrameworkUiRuntime
---@field suppressOverlays fun(): AdamantModpackLib.UiSuppressionToken
---@field areOverlaysSuppressed fun(): boolean

---@class AdamantModpackLib.AuthorFallbackUi
---@field attachGuiOnce fun(register: fun(ui: AdamantModpackLib.FallbackUiBridge)): boolean

---@class AdamantModpackLib.AuthorHooks
---@field wrap fun(path: string, keyOrHandler: string|fun(base: function, ...: any): any, maybeHandler?: fun(base: function, ...: any): any)
---@field override fun(path: string, keyOrReplacement: string|fun(...: any): any, maybeReplacement?: fun(...: any): any)
---@field contextWrap fun(path: string, keyOrContext: string|fun(...: any): any, maybeContext?: fun(...: any): any)

---@class AdamantModpackLib.AuthorIntegrationRegistration
---@field providerId string Public provider identity returned to consumers.
---@field methods table<string, AdamantModpackLib.AuthorIntegrationMethod> Provider methods exposed to consumers.
---@field events table<string, true>? Provider events this integration may emit. `providerChanged` is reserved by Lib.

---@class AdamantModpackLib.AuthorIntegrationMethod
---@field reads string[]? Storage aliases this provider method may read from the provider's staged state.
---@field handler fun(scope: AdamantModpackLib.IntegrationReadScope, ...): any Provider method implementation.

---@class AdamantModpackLib.IntegrationReadScope
---@field read fun(alias: string, ...): any Read a declared alias from the provider's staged state.
---@field get fun(alias: string): AdamantModpackLib.StorageFieldReadOnly|AdamantModpackLib.StorageTableReadOnly|nil
---Get a declared read-only storage ref.

---@class AdamantModpackLib.AuthorIntegrations
---@field provide fun(id: string, opts: AdamantModpackLib.AuthorIntegrationRegistration): table
---@field poll fun(id: string, methodName: string, fallback: any, ...): any, string?
---@field listen fun(id: string, eventName: string, callback: fun(payload: any, providerId: string)): table
---@field emit fun(id: string, eventName: string, payload: any): boolean, integer|string

---@class AdamantModpackLib.AuthorMutation
---@field patch fun(callback: fun(
---    plan: AdamantModpackLib.MutationPlan,
---    host: AdamantModpackLib.AuthorHost,
---    store: AdamantModpackLib.Store
---))

---@class AdamantModpackLib.AuthorCache
---@field currentRun AdamantModpackLib.AuthorCurrentRunCache
---@field persistent AdamantModpackLib.AuthorPersistentCache
---@field shared AdamantModpackLib.AuthorSharedCache

---@class AdamantModpackLib.AuthorCurrentRunCache
---@field get fun(key: string, factory?: fun(): table): table?
---@field peek fun(key: string): table?
---@field clear fun(key: string): boolean

---@class AdamantModpackLib.AuthorPersistentCache
---@field read fun(key: string, defaultValue?: boolean|number|string): boolean|number|string?
---@field write fun(key: string, value: boolean|number|string): boolean
---@field clear fun(key: string): boolean
---@field has fun(key: string): boolean
---@field snapshotRef fun(key: string, defaultValue?: boolean|number|string): AdamantModpackLib.AuthorPersistentSnapshotRef

---@class AdamantModpackLib.AuthorPersistentSnapshotRef
---@field get fun(self?: AdamantModpackLib.AuthorPersistentSnapshotRef): boolean|number|string?
---@field set fun(self: AdamantModpackLib.AuthorPersistentSnapshotRef, value: boolean|number|string): boolean
---@field clear fun(self?: AdamantModpackLib.AuthorPersistentSnapshotRef): boolean
---@field has fun(self?: AdamantModpackLib.AuthorPersistentSnapshotRef): boolean
---@field refresh fun(self?: AdamantModpackLib.AuthorPersistentSnapshotRef): boolean|number|string?

---@class AdamantModpackLib.AuthorSharedCache
---@field publish fun(id: string, opts?: table): boolean Declare an owner-published shared cache projection before activation.
---@field read fun(id: string, fallback: any): any Read an owner-published shared cache projection.
---@field write fun(id: string, value: any): boolean Write an owned shared cache projection after activation.
---@field clear fun(id: string): boolean Clear an owned shared cache projection after activation.

---@class AdamantModpackLib.ModuleDefinition
---@field modpack? string Coordinator pack id for coordinated modules.
---@field id string Stable module id within the pack.
---@field name string Display name.
---@field shortName? string Short UI label.
---@field tooltip? string UI tooltip.
---@field storage? AdamantModpackLib.StorageSchema Module storage schema.
---@field actions? table<string, AdamantModpackLib.DrawActionHandler> Module draw-action handlers keyed by action id.
---@field hashGroupPlan? AdamantModpackLib.HashGroupPlan Hash compaction hints.

---@alias AdamantModpackLib.DrawActionHandler fun(
---    state: AdamantModpackLib.DrawState,
---    services: AdamantModpackLib.DrawServices,
---    value: any
---)

---@class AdamantModpackLib.PreparedDefinition: AdamantModpackLib.ModuleDefinition

---@class AdamantModpackLib.MutationBundle
---@field patchMutation? fun(
---    plan: AdamantModpackLib.MutationPlan,
---    host: AdamantModpackLib.AuthorHost?,
---    store: AdamantModpackLib.Store
---)

---@class AdamantModpackLib.ModuleCreateOpts
---@field pluginGuid string Plugin guid captured at module file load time.
---@field config table Module config table.
---@field modpack? string Module pack id used by Framework grouping.
---@field id string Stable module id.
---@field name string Display name.
---@field shortName? string Short display name.
---@field tooltip? string UI tooltip.
---@field storage? AdamantModpackLib.StorageSchema Raw storage schema.
---@field actions? table<string, AdamantModpackLib.DrawActionHandler> Draw-action handlers keyed by action id.
---@field hashGroupPlan? AdamantModpackLib.HashGroupPlan Raw hash/profile group plan.
--- Post-commit observer for rebuilding derived runtime/UI structures.
---@field onSettingsCommitted? fun(
---    host: AdamantModpackLib.AuthorHost,
---    store: AdamantModpackLib.Store,
---    commit: AdamantModpackLib.CommitContext
---)
---@field drawTab fun(
---    draw: AdamantModpackLib.DrawContext,
---    state: AdamantModpackLib.DrawState,
---    actions: AdamantModpackLib.DrawActions,
---    services: AdamantModpackLib.DrawServices
---)
---@field drawQuickContent? fun(
---    draw: AdamantModpackLib.DrawContext,
---    state: AdamantModpackLib.DrawState,
---    actions: AdamantModpackLib.DrawActions,
---    services: AdamantModpackLib.DrawServices
---)

---Draw-phase immediate UI surface. `widgets` and `nav` methods require an active draw callback; `imgui` is the raw environment ImGui table.
---@class AdamantModpackLib.DrawContext
---@field imgui table Raw ImGui backend table for custom layout and controls.
---@field widgets AdamantModpackLib.DrawWidgetsApi
---@field nav AdamantModpackLib.DrawNavApi

---@class AdamantModpackLib.ModuleHost
---@field getHostId fun(): string
---@field getModuleId fun(): string
---@field getPackId fun(): string?
---@field getMeta fun(): AdamantModpackLib.ModuleMeta
---@field affectsRunData fun(): boolean
---@field getHashHints fun(): AdamantModpackLib.HashGroupPlan?
---@field getStorage fun(): AdamantModpackLib.StorageSchema?
---@field read fun(alias: string): any
---@field writeAndFlush fun(alias: string, value: any): boolean
---@field stage fun(alias: string, value: any): boolean
---@field flush fun(): boolean
---@field reloadFromConfig fun()
---@field resync fun(): string[]
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
---@field handleHostGuiClosed fun()

---@class AdamantModpackLib.CoordinatorConfig
---@field ModEnabled boolean

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
---@field label? string
---@field tooltip? string
---@field maxLen? number
---@field controlWidth? number
---@field controlGap? number
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when edited.
---@field value? any Staged action payload. Defaults to the edited text.

---@class AdamantModpackLib.DropdownOpts
---@field id? string|number
---@field label? string
---@field tooltip? string
---@field values? AdamantModpackLib.ChoiceValue[]
---@field default? AdamantModpackLib.ChoiceValue
---@field displayValues? AdamantModpackLib.ChoiceDisplayValues
---@field valueColors? AdamantModpackLib.ValueColorMap
---@field controlWidth? number
---@field controlGap? number
---@field action? AdamantModpackLib.DrawActionRef Staged action ref to replace when selection changes.
---@field value? any Staged action payload. Defaults to the selected value.

---@class AdamantModpackLib.PackedDropdownOpts
---@field id? string|number
---@field label? string
---@field tooltip? string
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
---@field default? AdamantModpackLib.ChoiceValue
---@field displayValues? AdamantModpackLib.ChoiceDisplayValues
---@field valueColors? AdamantModpackLib.ValueColorMap
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

---@class AdamantModpackLib.RetainedOverlayColumn
---@field key? string Stable column key used by retained values.
---@field componentName? string Explicit retained HUD component name for this column.
---@field minWidth? number Reserved layout width used to keep following columns aligned.
---@field justify? "Left"|"Center"|"Right" Column text justification.
---@field visible? boolean|fun(): boolean
---@field textArgs? table Text style overrides.

---@class AdamantModpackLib.RetainedLineSpec
---@field componentName? string Base retained HUD component name.
---@field region? string Stack region name. Defaults to `middleRightStack`.
---@field order? integer Sort key within the region.
---@field columnGap? number Reserved space between columns.
---@field columns? AdamantModpackLib.RetainedOverlayColumn[] Ordered columns, declared left-to-right.
---@field visible? boolean|fun(): boolean
---@field minWidth? number Width for one-column convenience lines.
---@field justify? "Left"|"Center"|"Right" Justification for one-column convenience lines.
---@field textArgs? table Text style overrides for one-column convenience lines.

---@class AdamantModpackLib.RetainedTableSpec
---@field componentName? string Base retained HUD component name.
---@field region? string Stack region name. Defaults to `middleRightStack`.
---@field order? integer Sort key for the first row within the region.
---@field maxRows integer Maximum retained rows to allocate.
---@field columnGap? number Reserved space between columns.
---@field columns AdamantModpackLib.RetainedOverlayColumn[] Ordered columns, declared left-to-right.
---@field visible? boolean|fun(): boolean

---@class AdamantModpackLib.OverlayProjectionContext
---@field read fun(alias: string): any
---@field isEnabled fun(): boolean
---@field log fun(fmt: string, ...)
---@field logIf fun(fmt: string, ...)
---@field setLine fun(name: string, values: table|string): boolean
---@field setTable fun(name: string, rows: table[]): boolean
---@field setCell fun(tableName: string, rowKey: any, columnKey: string, value: any): boolean
---@field refresh fun(name: string): boolean
---@field refreshRegion fun(region: string)
---@field refreshAll fun()

---@class AdamantModpackLib.OverlayHookEvent
---@field path string
---@field args table
---@field result any
---@field results table

---@class AdamantModpackLib.RetainedOverlayRegistrar
---@field order table<string, integer> Shared overlay order bands.
---@field createLine fun(name: string, spec: AdamantModpackLib.RetainedLineSpec)
---@field createTable fun(name: string, spec: AdamantModpackLib.RetainedTableSpec)
---@field onCommit fun(callback: fun(ctx: AdamantModpackLib.OverlayProjectionContext, commit: AdamantModpackLib.CommitContext))
---@field onInterval fun(
---    name: string,
---    seconds: number,
---    callback: fun(ctx: AdamantModpackLib.OverlayProjectionContext, event: table),
---    opts?: table
---)
---@field afterHook fun(
---    path: string,
---    callback: fun(ctx: AdamantModpackLib.OverlayProjectionContext, event: AdamantModpackLib.OverlayHookEvent)
---)

---@class AdamantModpackLib.SystemOverlayRegistrar
---@field createLine fun(name: string, spec: AdamantModpackLib.RetainedLineSpec)
---@field onCommit fun(callback: fun(ctx: AdamantModpackLib.OverlayProjectionContext, commit: AdamantModpackLib.CommitContext))

---@class AdamantModpackLib.UiSuppressionToken
---@field release fun()

---Draw-phase widget helpers. Call from `drawTab(...)` or `drawQuickContent(...)`.
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

---Draw-phase navigation helpers. Call from `drawTab(...)` or `drawQuickContent(...)`.
---@class AdamantModpackLib.DrawNavApi
---@field verticalTabs fun(opts?: AdamantModpackLib.VerticalTabsOpts): string|number?

---Internal constructed module state bundle.
---@class AdamantModpackLib.ModuleState
---@field persistentState AdamantModpackLib.PersistentState
---@field stagedState AdamantModpackLib.StagedState

---@param opts AdamantModpackLib.ModuleCreateOpts
---@return AdamantModpackLib.AuthorHost? host
---@return AdamantModpackLib.Store? store
---@return string? err
function lib.createModule(opts)
end

---@param frameworkPluginGuid string Must be `adamant-ModpackFramework`.
---@return AdamantModpackLib.FrameworkRuntime runtime
function lib.createFrameworkRuntime(frameworkPluginGuid)
end

return lib
