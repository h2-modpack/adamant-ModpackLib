std = "lua52"
max_line_length = 140

globals = { 
    "rom", 
    "public", 
    "config", 
    "modutil", 
    "game", 
    "chalk", 
    "reload", 
    "_PLUGIN", 
    "AdamantModpackLib_Internal", 
    "GetConfigBackend",
    "ScreenData"
    }
read_globals = { 
    "imgui", 
    "import_as_fallback", 
    "import",
    "HUDScreen",
    "ImGuiTreeNodeFlags",
    "ModifyTextBox",
    "ImGuiComboFlags",
    "ImGuiCol"
    }
exclude_files = { "src/vendor/**/*.lua", "src/**/*template*.lua" }
