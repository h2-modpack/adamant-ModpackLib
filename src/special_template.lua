-- =============================================================================
-- ADAMANT SPECIAL MODULE TEMPLATE
-- =============================================================================
-- Copy this file as src/main.lua in a new mod folder.
-- Fill in the sections marked FILL below.
--
-- Special modules get their own sidebar tab in Core's UI and can encode
-- custom state into the config hash. They also render standalone when Core
-- is not installed.
--
-- Staging and sync are handled by lib.createSpecialState.
-- Hashing is handled by Core via definition.stateSchema — modules don't encode/decode.
--
-- Public API wired automatically:
--   public.SnapshotStaging          -- re-read config into staging
--   public.SyncToConfig             -- flush staging to config
--   public.definition.stateSchema   -- declares state shape for Core to hash
--
-- You implement (optional):
--   public.DrawTab(imgui, onChanged, theme)         -- full tab content
--   public.DrawQuickContent(imgui, onChanged, theme) -- quick setup snippet

local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods['SGG_Modding-ModUtil']
chalk = mods['SGG_Modding-Chalk']
reload = mods['SGG_Modding-ReLoad']
local lib = mods['adamant-Modpack_Lib']

config = chalk.auto('config.lua')
public.config = config

local backup, revert = lib.createBackupSystem()

-- =============================================================================
-- FILL: Module definition
-- =============================================================================

public.definition = {
    id           = "",       -- Unique key, e.g. "FirstHammer"
    name         = "",       -- Display name, e.g. "First Hammer Selection"
    tabLabel     = "",       -- Sidebar tab label in Core UI, e.g. "Hammers"
    category     = "",       -- For standalone grouping, e.g. "RunModifiers"
    group        = "",       -- UI group header
    tooltip      = "",       -- Hover text
    default      = false,    -- Default enabled state
    special      = true,     -- Marks this as a special module
    dataMutation = false,    -- true if apply() modifies game tables
}

-- =============================================================================
-- FILL: Module data & constants
-- =============================================================================

-- Define your module-specific data here (lookup tables, option lists, etc.)
-- Example:
-- local MY_OPTIONS = { "OptionA", "OptionB", "OptionC" }

-- =============================================================================
-- FILL: State schema & staging
-- =============================================================================
-- Declare your config shape on definition.stateSchema.
-- Core uses this for hashing and profiles. lib.createSpecialState gives you
-- a plain staging table for fast UI access.
--
-- Supported field types:
--   "checkbox" — single boolean toggle
--     { type="checkbox", configKey="X", default=false }
--
--   "dropdown" — pick one from a list (combo box)
--     { type="dropdown", configKey="X", values={...}, default="" }
--
--   "radio"    — pick one from a list (radio buttons)
--     { type="radio", configKey="X", values={...}, default="" }
--
-- configKey can be a string or a table path for nested config:
--   configKey = { "ParentTable", "ChildKey" }  -->  config.ParentTable.ChildKey

public.definition.stateSchema = {
    -- Example "dropdown" field (single selection):
    -- {
    --     configKey = "Mode",
    --     type      = "dropdown",
    --     values    = { "Normal", "Fast", "Slow" },
    --     default   = "Normal",
    -- },
}

local staging, snapshotStaging, syncToConfig =
    lib.createSpecialState(config, public.definition.stateSchema)

-- =============================================================================
-- FILL: apply() — mutate game data or set initial state
-- =============================================================================

local function apply()
end

-- =============================================================================
-- FILL: registerHooks() — wrap game functions
-- =============================================================================

local function registerHooks()
    -- modutil.mod.Path.Wrap("SomeGameFunction", function(baseFunc, ...)
    --     if not lib.isEnabled(config) then return baseFunc(...) end
    --     return baseFunc(...)
    -- end)
end

-- =============================================================================
-- FILL: UI rendering
-- =============================================================================
-- Draw functions receive an optional `theme` table (Core.Theme when hosted,
-- nil when standalone). Pick the keys you need, falling back to baked-in defaults.
--
-- Available theme keys (when hosted by Core):
--   theme.LABEL_OFFSET   -- fraction of window width for label column
--   theme.FIELD_MEDIUM   -- fraction of window width for medium input fields
--   theme.FIELD_NARROW   -- fraction for narrow fields
--   theme.FIELD_WIDE     -- fraction for wide fields
--   theme.colors         -- color table
--   theme.DrawColoredText(ui, text, color)
--   theme.PushTheme(ui) / theme.PopTheme(ui)

local function DrawMainContent(ui, onChanged, theme)
    -- Your full tab UI here.
    -- Use `staging` for reads/writes (it's a plain table, fast for UI).
    -- Call onChanged() after any user interaction that modifies staging.
    ui.Text("TODO: implement tab content")
end

local function DrawQuickSnippet(ui, onChanged, theme)
    -- Abbreviated UI for the Quick Setup tab (optional).
    -- Typically shows only the most relevant option(s).
    ui.Text("TODO: implement quick content")
end

-- =============================================================================
-- PUBLIC API (generic special module contract)
-- =============================================================================

public.definition.apply = apply
public.definition.revert = revert

-- State management — wired directly from lib.createSpecialState
public.SnapshotStaging    = snapshotStaging
public.SyncToConfig       = syncToConfig

--- Draw the full tab content (Core renders the enable checkbox above this).
function public.DrawTab(imgui, onChanged, theme)
    imgui.Spacing()
    DrawMainContent(imgui, onChanged, theme)
end

--- Draw quick-access content for the Quick Setup tab.
function public.DrawQuickContent(imgui, onChanged, theme)
    DrawQuickSnippet(imgui, onChanged, theme)
end

-- =============================================================================
-- Wiring
-- =============================================================================

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(function()
        import_as_fallback(rom.game)
        registerHooks()
        if lib.isEnabled(config) then apply() end
    end)
end)

-- =============================================================================
-- STANDALONE UI (renders when Core is not installed)
-- =============================================================================

local showWindow = false

rom.gui.add_imgui(function()
    if mods['adamant-Modpack_Core'] then return end
    if not showWindow then return end

    if rom.ImGui.Begin(public.definition.name, true) then
        local val, chg = rom.ImGui.Checkbox("Enabled", config.Enabled)
        if chg then
            config.Enabled = val
            if val then apply() else revert() end
        end
        rom.ImGui.Separator()
        rom.ImGui.Spacing()
        DrawMainContent(rom.ImGui, syncToConfig, nil)
        rom.ImGui.End()
    else
        showWindow = false
    end
end)

rom.gui.add_to_menu_bar(function()
    if mods['adamant-Modpack_Core'] then return end
    if rom.ImGui.BeginMenu("adamant") then
        if rom.ImGui.MenuItem(public.definition.name) then
            showWindow = not showWindow
        end
        rom.ImGui.EndMenu()
    end
end)
