return {
    ["coordinator.invalid_registration"] = {
        severity = "error",
        description = "Coordinator registration requires a stable pack id and config table.",
    },
    ["coordinator.invalid_rebuild_callback"] = {
        severity = "error",
        description = "Coordinator rebuild callbacks must be callable so structural reloads can be delegated.",
    },

    ["definition.invalid_field_type"] = {
        severity = "error",
        description = "Definition metadata fields should use the expected public contract types.",
    },
    ["definition.invalid_args"] = {
        severity = "error",
        description = "Definition preparation requires valid structural state and definition arguments.",
    },
    ["definition.missing_id"] = {
        severity = "error",
        description = "Definitions must declare a stable module id.",
    },
    ["definition.missing_name"] = {
        severity = "error",
        description = "Definitions must declare a stable display name.",
    },
    ["definition.structural_reload_required"] = {
        severity = "warn",
        description = "An uncoordinated structural hot reload cannot be reconciled without a full reload.",
    },
    ["definition.unknown_key"] = {
        severity = "error",
        description = "Unknown definition keys are invalid and may indicate stale author code.",
    },
    ["definition.reserved_storage_alias"] = {
        severity = "error",
        description = "Built-in storage aliases are owned by Lib and cannot be declared by modules.",
    },

    ["cache.invalid_args"] = {
        severity = "error",
        description = "Cache access requires valid owner id and key arguments.",
    },
    ["cache.invalid_bucket"] = {
        severity = "error",
        description = "Cache buckets must remain tables owned by Lib.",
    },
    ["cache.invalid_factory"] = {
        severity = "error",
        description = "Cache factories must be functions that return tables.",
    },

    ["controls.invalid_declaration"] = {
        severity = "error",
        description = "Control declarations require stable names, known templates, and valid instance fields.",
    },
    ["controls.duplicate_name"] = {
        severity = "error",
        description = "Control template, instance, and field names must be unique in their scope.",
    },
    ["controls.unknown_template"] = {
        severity = "error",
        description = "Control instances can only reference templates declared by the module.",
    },
    ["controls.invalid_template"] = {
        severity = "error",
        description = "Control templates must expose valid factory, storage, and draw/view callbacks.",
    },
    ["controls.invalid_field"] = {
        severity = "error",
        description = "Control storage fields must compile into valid private storage declarations.",
    },
    ["controls.unknown_field_alias"] = {
        severity = "error",
        description = "Control field and table methods can only access aliases declared by the control template binding.",
    },
    ["controls.unavailable_field"] = {
        severity = "error",
        description = "Control template refs can only use fields available on the current runtime or UI surface.",
    },
    ["controls.unknown_control"] = {
        severity = "error",
        description = "Control access requires a declared control instance.",
    },
    ["controls.invalid_render_target"] = {
        severity = "error",
        description = "Draw control rendering requires a Lib-created control ref.",
    },
    ["controls.unknown_view"] = {
        severity = "error",
        description = "Draw control rendering can only use views declared by the control template.",
    },

    ["game_deps.invalid_boundary"] = {
        severity = "error",
        description = "Game dependency reads must match the expected game-global or ROM function shape.",
    },

    ["module.invalid_create_opts"] = {
        severity = "error",
        description = "Module creation requires a prepared definition, pluginGuid, state handles, drawTab, and callbacks.",
    },
    ["managed_module.invalid_activate_opts"] = {
        severity = "error",
        description = "Managed module activation requires a constructed module.",
    },
    ["managed_module.already_activated"] = {
        severity = "error",
        description = "Managed modules can only be activated once.",
    },
    ["managed_module.activation_in_progress"] = {
        severity = "error",
        description = "Managed module activation cannot be called recursively from activation callbacks.",
    },
    ["managed_module.not_activated"] = {
        severity = "error",
        description = "Side-effecting managed module methods require explicit activation first.",
    },
    ["module.unknown_opt"] = {
        severity = "error",
        description = "Module creation only accepts known construction options.",
    },
    ["managed_module.enable_transition_failed"] = {
        severity = "warn",
        description = "A module enable/disable transition failed and the UI state may need resync.",
    },
    ["managed_module.staged_state_commit_failed"] = {
        severity = "warn",
        description = "A staged UI state commit failed and Lib attempted to restore the previous config state.",
    },
    ["managed_module.structural_rebuild_unavailable"] = {
        severity = "error",
        description = "A coordinated structural reload was detected but no rebuild callback accepted it.",
    },
    ["module.create_failed"] = {
        severity = "warn",
        description = "Safe module construction failed; the caller may skip this module and continue loading siblings.",
    },
    ["managed_module.activate_failed"] = {
        severity = "warn",
        description = "Safe module activation failed; the caller may skip this module and continue loading siblings.",
    },
    ["managed_module.activation_rollback_failed"] = {
        severity = "warn",
        description = "Candidate activation rollback had secondary cleanup failures.",
    },
    ["managed_module.retire_failed"] = {
        severity = "warn",
        description = "Old module resource retirement had cleanup failures after a replacement module was published.",
    },

    ["hooks.invalid_registration"] = {
        severity = "error",
        description = "Hook registration requires valid owners, paths, and callback functions.",
    },
    ["hooks.invalid_context"] = {
        severity = "error",
        description = "Hook context helper calls must stay inside the active context callback.",
    },
    ["hooks.inactive_override"] = {
        severity = "error",
        description = "Inactive hook replacements should not be invoked after refresh invalidation.",
    },
    ["hooks.modutil_unavailable"] = {
        severity = "error",
        description = "Hook registration requires SGG_Modding-ModUtil to be available.",
    },

    ["shared.invalid_args"] = {
        severity = "error",
        description = "Shared event/value calls require valid ids, event names, listener callbacks, and declarations.",
    },
    ["shared.invalid_value"] = {
        severity = "error",
        description = "Shared values must be scalars or tables with supported read-only view semantics.",
    },
    ["shared.duplicate_publisher"] = {
        severity = "error",
        description = "Shared value ids can only have one active publishing owner.",
    },
    ["shared.not_owner"] = {
        severity = "error",
        description = "Shared value writes require the active publishing owner.",
    },
    ["shared.listener_failed"] = {
        severity = "warn",
        description = "A shared event listener failed; Lib continued delivering the event to other listeners.",
    },
    ["shared.event_cycle"] = {
        severity = "warn",
        description = "Shared event delivery stopped because queued nested events exceeded the cycle guard.",
    },

    ["system_scope.invalid_owner"] = {
        severity = "error",
        description = "System scopes require a stable owner id.",
    },
    ["framework_runtime.invalid_framework_plugin"] = {
        severity = "error",
        description = "Framework runtime construction requires the Framework plugin guid.",
    },
    ["framework_runtime.unexpected_pack"] = {
        severity = "error",
        description = "Framework runtime construction is not pack-scoped; pack ids belong to overlay definitions.",
    },
    ["framework_runtime.invalid_pack"] = {
        severity = "error",
        description = "Framework overlay declarations require a stable pack id.",
    },
    ["modpack.overlays.invalid_pack"] = {
        severity = "error",
        description = "Modpack overlay declarations require a stable pack id.",
    },
    ["framework_runtime.invalid_debug_mode"] = {
        severity = "error",
        description = "Framework runtime diagnostics require boolean Lib debug mode values.",
    },
    ["framework_runtime.invalid_overlay_scope"] = {
        severity = "error",
        description = "Framework runtime overlay declarations require a stable scoped name.",
    },
    ["modpack.overlays.invalid_scope"] = {
        severity = "error",
        description = "Modpack overlay declarations require a stable scoped name.",
    },

    ["fallback_ui.invalid_args"] = {
        severity = "error",
        description = "Fallback UI attachment requires a managed module and one-time registration callback.",
    },

    ["mutation.invalid_runtime_key"] = {
        severity = "error",
        description = "Mutation lifecycle operations require a stable plugin guid runtime key.",
    },
    ["mutation.invalid_registration"] = {
        severity = "error",
        description = "Mutation declarations require a managed module and a patch callback before activation.",
    },

    ["lifecycle.on_commit_failed"] = {
        severity = "warn",
        description = "A module onCommit callback raised an error.",
    },
    ["lifecycle.on_commit_false"] = {
        severity = "warn",
        description = "A module onCommit callback returned false.",
    },
    ["lifecycle.staged_state_drift_detected"] = {
        severity = "warn",
        description = "Staged UI state drifted from persisted config and was reloaded.",
    },
    ["lifecycle.staged_state_rollback_reapply_failed"] = {
        severity = "warn",
        description = "A staged state rollback could not fully reapply the previous mutation state.",
    },

    ["overlays.invalid_registration"] = {
        severity = "error",
        description = "Overlay registration requires valid ids, draw functions, and column descriptors.",
    },

    ["actions.invalid_key"] = {
        severity = "error",
        description = "Action refs require a non-empty string action key.",
    },
    ["actions.unknown_key"] = {
        severity = "error",
        description = "Draw actions must be declared by the module definition before use.",
    },
    ["actions.private_key"] = {
        severity = "error",
        description = "Private Lib action keys are not available through author-facing action surfaces.",
    },
    ["api.invalid_method_call"] = {
        severity = "error",
        description = "Object handle methods must be called with Lua colon method syntax.",
    },

    ["widgets.invalid_field_target"] = {
        severity = "error",
        description = "Bound value widgets require Lib-created StorageField targets.",
    },
    ["widgets.invalid_action"] = {
        severity = "error",
        description = "Widget action options must be draw action refs.",
    },
    ["staged_state.unknown_alias"] = {
        severity = "error",
        description = "Staged state operations only accept declared storage aliases.",
    },
    ["staged_state.invalid_table_alias"] = {
        severity = "error",
        description = "Staged state table access requires a table root alias, not scalar or packed-bit aliases.",
    },
    ["staged_state.invalid_surface"] = {
        severity = "error",
        description = "Staged state writes cannot mutate status storage.",
    },
    ["status.unknown_alias"] = {
        severity = "error",
        description = "Status operations only accept aliases declared through module.status.define.",
    },
    ["status.invalid_alias"] = {
        severity = "error",
        description = "Status aliases must be stable public identifiers declared through module.status.define.",
    },
    ["status.invalid_declaration_set"] = {
        severity = "error",
        description = "Status declarations must be provided as a table keyed by status alias.",
    },
    ["status.invalid_declaration"] = {
        severity = "error",
        description = "Each status declaration must be a valid storage descriptor table.",
    },
    ["status.invalid_field"] = {
        severity = "error",
        description = "Status declarations cannot override fields owned by Lib status compilation.",
    },
    ["status.missing_persist"] = {
        severity = "error",
        description = "Status declarations must explicitly choose whether values persist across sessions.",
    },
    ["status.invalid_persist"] = {
        severity = "error",
        description = "Status declaration persist values must be boolean.",
    },
    ["status.invalid_surface"] = {
        severity = "error",
        description = "Status operations can only access runtime-authored status aliases.",
    },
    ["status.invalid_table_alias"] = {
        severity = "error",
        description = "Status table access requires a table root alias, not scalar or packed-bit aliases.",
    },
    ["storage.invalid_field_alias"] = {
        severity = "error",
        description = "Storage fields require a non-empty storage alias.",
    },
    ["storage.private_alias"] = {
        severity = "error",
        description = "Private Lib storage aliases are not accessible through author-facing storage refs.",
    },
    ["storage.invalid_field_owner"] = {
        severity = "error",
        description = "Storage fields require a storage owner exposing read and schema access.",
    },
    ["storage.unknown_field_alias"] = {
        severity = "error",
        description = "Storage fields can only target prepared storage aliases.",
    },
    ["storage.invalid_field_args"] = {
        severity = "error",
        description = "Storage field reads do not accept nested path arguments.",
    },
    ["storage.readonly_field"] = {
        severity = "error",
        description = "Writable widget fields require a writable storage owner.",
    },
    ["store.invalid_create_args"] = {
        severity = "error",
        description = "Store creation requires a prepared module definition.",
    },
    ["store.invalid_table_alias"] = {
        severity = "error",
        description = "Store table access requires a table root alias, not scalar or packed-bit aliases.",
    },
    ["store.invalid_surface"] = {
        severity = "error",
        description = "Store operations cannot access staged-only transient UI storage.",
    },
    ["store.unknown_alias"] = {
        severity = "error",
        description = "Store operations only accept declared storage aliases.",
    },
    ["storage.duplicate_alias"] = {
        severity = "error",
        description = "Storage aliases must be unique across roots and packed child aliases.",
    },
    ["storage.hash_requires_persist"] = {
        severity = "error",
        description = "Hash/profile storage must be persisted so values can round-trip.",
    },
    ["storage.hash_requires_setting"] = {
        severity = "error",
        description = "Runtime-owned storage cannot participate in hashes.",
    },
    ["storage.invalid_axis_type"] = {
        severity = "error",
        description = "Storage axis options and numeric bounds must use supported value types.",
    },
    ["storage.invalid_default"] = {
        severity = "error",
        description = "Storage defaults must match the declared storage type.",
    },
    ["storage.invalid_node"] = {
        severity = "error",
        description = "Storage schema entries must be valid typed nodes with aliases.",
    },
    ["storage.invalid_packed_bit"] = {
        severity = "error",
        description = "Packed bit declarations must have valid aliases, offsets, widths, and types.",
    },
    ["storage.invalid_schema"] = {
        severity = "error",
        description = "Storage schemas must be valid arrays of storage nodes.",
    },
    ["storage.unknown_field"] = {
        severity = "error",
        description = "Storage nodes only accept fields supported by their declared storage type.",
    },
    ["storage.invalid_table_row"] = {
        severity = "error",
        description = "Table row schemas must be flat storage schemas owned by the table root.",
    },
    ["storage.missing_persisted_default"] = {
        severity = "error",
        description = "Persisted storage roots must declare effective defaults.",
    },
    ["storage.packed_child_default_mismatch"] = {
        severity = "debug",
        description = "Packed child defaults should match the encoded packedInt root default.",
    },
    ["storage.readonly_table_handle"] = {
        severity = "error",
        description = "Read-only table handles cannot perform row mutations.",
    },
    ["storage.unknown_table_row_alias"] = {
        severity = "error",
        description = "Table row reads and writes only accept aliases declared by the table row schema.",
    },
    ["storage.invalid_table_handle_args"] = {
        severity = "error",
        description = "Table handle methods require a valid handle receiver and method arguments.",
    },
}
