std = "lua52"
max_line_length = 120

-- Variables the scripts actively define or mutate
globals = {
    "rom",
    "config",
    "modutil",
    "public",
    "_PLUGIN",
    "game",
    "chalk",
    "reload"
}

-- Variables provided by the environment strictly for reading
read_globals = {
    "imgui",
    "import_as_fallback",
    "import",
    "ModifyTextBox",
    "MockDiscovery"
}

