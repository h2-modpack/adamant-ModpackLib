return {
    DebugMode = false,
    -- Comma-separated hotkey bindings other tools use, such as "Ctrl+F5,F8". Lib never dispatches
    -- a module hotkey on a reserved binding. Edited from the modpack window's Hotkeys page.
    ReservedHotkeys = "",
    Diagnostics = {
        configBackend = {
            label = "Config Backend Diagnostics",
            enabled = false,
        },
    },
}
