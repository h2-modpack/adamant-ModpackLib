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
    ["cache.invalid_value"] = {
        severity = "error",
        description = "Persistent cache values must be flat scalar values.",
    },

    ["game_deps.invalid_boundary"] = {
        severity = "error",
        description = "Game dependency reads must match the expected game-global or ROM function shape.",
    },

    ["host.invalid_create_opts"] = {
        severity = "error",
        description = "Module host creation requires prepared definition, pluginGuid, state handles, drawTab, and callbacks.",
    },
    ["host.invalid_activate_opts"] = {
        severity = "error",
        description = "Module host activation requires a constructed host.",
    },
    ["host.already_activated"] = {
        severity = "error",
        description = "Module hosts can only be activated once.",
    },
    ["host.activation_in_progress"] = {
        severity = "error",
        description = "Module host activation cannot be called recursively from activation callbacks.",
    },
    ["host.not_activated"] = {
        severity = "error",
        description = "Side-effecting module host methods require explicit activation first.",
    },
    ["host.unknown_opt"] = {
        severity = "error",
        description = "Module host creation only accepts known construction options.",
    },
    ["host.enable_transition_failed"] = {
        severity = "warn",
        description = "A module enable/disable transition failed and the UI state may need resync.",
    },
    ["host.staged_state_commit_failed"] = {
        severity = "warn",
        description = "A staged UI state commit failed and Lib attempted to restore the previous config state.",
    },
    ["host.structural_rebuild_unavailable"] = {
        severity = "error",
        description = "A coordinated structural reload was detected but no rebuild callback accepted it.",
    },
    ["host.create_failed"] = {
        severity = "warn",
        description = "Safe module construction failed; the caller may skip this module and continue loading siblings.",
    },
    ["host.activate_failed"] = {
        severity = "warn",
        description = "Safe module activation failed; the caller may skip this module and continue loading siblings.",
    },
    ["host.activation_rollback_failed"] = {
        severity = "warn",
        description = "Candidate activation rollback had secondary cleanup failures.",
    },
    ["host.retire_failed"] = {
        severity = "warn",
        description = "Old host resource retirement had cleanup failures after a replacement host was published.",
    },

    ["hooks.invalid_registration"] = {
        severity = "error",
        description = "Hook registration requires valid owners, paths, and callback functions.",
    },
    ["hooks.inactive_override"] = {
        severity = "error",
        description = "Inactive hook replacements should not be invoked after refresh invalidation.",
    },
    ["hooks.modutil_unavailable"] = {
        severity = "error",
        description = "Hook registration requires SGG_Modding-ModUtil to be available.",
    },

    ["integrations.invalid_args"] = {
        severity = "error",
        description = "Integration registry calls require non-empty ids and valid provider APIs.",
    },
    ["integrations.provider_failed"] = {
        severity = "warn",
        description = "An integration provider method failed; Lib returned the caller fallback.",
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
    ["framework_runtime.invalid_debug_mode"] = {
        severity = "error",
        description = "Framework runtime diagnostics require boolean Lib debug mode values.",
    },
    ["framework_runtime.invalid_overlay_scope"] = {
        severity = "error",
        description = "Framework runtime overlay declarations require a stable scoped name.",
    },

    ["fallback_ui.invalid_args"] = {
        severity = "error",
        description = "Fallback UI attachment requires a managed host and one-time registration callback.",
    },

    ["mutation.invalid_runtime_key"] = {
        severity = "error",
        description = "Mutation lifecycle operations require a stable plugin guid runtime key.",
    },
    ["mutation.invalid_registration"] = {
        severity = "error",
        description = "Mutation declarations require a managed module host and a patch callback before activation.",
    },

    ["lifecycle.on_settings_committed_failed"] = {
        severity = "warn",
        description = "A module onSettingsCommitted callback raised an error.",
    },
    ["lifecycle.on_settings_committed_false"] = {
        severity = "warn",
        description = "A module onSettingsCommitted callback returned false.",
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
    ["widgets.mismatched_field_owners"] = {
        severity = "error",
        description = "Stepped range widgets require both fields to share one storage owner.",
    },

    ["staged_state.unknown_alias"] = {
        severity = "error",
        description = "Staged state operations only accept declared storage aliases.",
    },
    ["staged_state.invalid_table_alias"] = {
        severity = "error",
        description = "Staged state table access requires a table root alias, not scalar or packed-bit aliases.",
    },
    ["staged_state.readonly_view_write"] = {
        severity = "error",
        description = "Staged state view is read-only; writes must go through stagedState.write.",
    },
    ["storage.invalid_field_alias"] = {
        severity = "error",
        description = "Storage fields require a non-empty storage alias.",
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
    ["store.invalid_config"] = {
        severity = "error",
        description = "Store creation requires a module config table for persisted backing values.",
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
