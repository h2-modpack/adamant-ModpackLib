-- =============================================================================
-- Test utilities: mock the engine globals so main.lua can load in plain Lua
-- =============================================================================

-- Mock public table (normally provided by ENVY)
public = {}

-- Mock _PLUGIN
_PLUGIN = { guid = "test-module" }

-- Deep copy helper (replaces rom.game.DeepCopyTable)
local function deepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deepCopy(v)
    end
    return copy
end

-- Mock rom
rom = {
    mods = {},
    game = {
        DeepCopyTable = deepCopy,
        SetupRunData = function() end,
    },
    ImGui = {},
    gui = {
        add_to_menu_bar = function() end,
        add_imgui = function() end,
    },
}

-- Mock ENVY: auto() returns an empty table, sets up public/envy globals
rom.mods['SGG_Modding-ENVY'] = {
    auto = function()
        return {}
    end,
}

-- Warning capture: collect warnings for assertions
Warnings = {}

function CaptureWarnings()
    Warnings = {}
    -- Enable debug mode so warn() actually fires
    rom.mods['adamant-Modpack_Core'] = {
        config = { ModEnabled = true, DebugMode = true },
    }
    -- Override print to capture warnings
    _originalPrint = print
    print = function(msg)
        table.insert(Warnings, msg)
    end
end

function RestoreWarnings()
    print = _originalPrint or print
    Warnings = {}
end

-- Load the library (runs once, populates `public`)
dofile("src/main.lua")

-- Alias for convenience
lib = public
