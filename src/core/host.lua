local internal = AdamantModpackLib_Internal
local _coordinators = internal.coordinators
public.host = public.host or {}
local host = public.host

---@class DerivedTextEntry
---@field alias string
---@field compute fun(uiState: UiState): string|number|boolean|nil
---@field signature fun(uiState: UiState): any|nil

---@class DerivedTextCacheEntry
---@field signature any
---@field value string

---@class StandaloneOpts
---@field windowTitle string|nil
---@field drawTab fun(imgui: table, uiState: UiState|nil)|nil
---@field getDrawTab fun(): fun(imgui: table, uiState: UiState|nil)|nil|nil

---@class StandaloneRuntime
---@field renderWindow fun()
---@field addMenuBar fun()

--- Recomputes derived text aliases for a UI state and optionally caches computed signatures and values.
---@param uiState UiState UI state used to read view data and write derived aliases.
---@param entries DerivedTextEntry[] Ordered list of derived-text descriptors with `alias`, `compute`, and optional `signature`.
---@param cache table<string, DerivedTextCacheEntry>|nil Optional cache table keyed by alias.
---@return boolean changed True when any derived alias value changed.
function host.runDerivedText(uiState, entries, cache)
    if not uiState or type(uiState.set) ~= "function" or type(uiState.view) ~= "table" then
        if internal.logging and internal.logging.warnIf then
            internal.logging.warnIf("runDerivedText: uiState is missing or malformed; pass skipped")
        end
        return false
    end
    if type(entries) ~= "table" then
        return false
    end

    local changed = false
    local derivedCache = type(cache) == "table" and cache or nil

    for index, entry in ipairs(entries) do
        local alias = type(entry) == "table" and entry.alias or nil
        local compute = type(entry) == "table" and entry.compute or nil
        if type(alias) ~= "string" or alias == "" then
            if internal.logging and internal.logging.warnIf then
                internal.logging.warnIf("runDerivedText: entries[%d].alias must be a non-empty string", index)
            end
        elseif type(compute) ~= "function" then
            if internal.logging and internal.logging.warnIf then
                internal.logging.warnIf("runDerivedText: entries[%d].compute must be a function", index)
            end
        else
            local cached = derivedCache and derivedCache[alias] or nil
            local currentValue = uiState.view[alias]
            local signatureFn = entry.signature
            local signature = nil
            local useCachedValue = false

            if type(signatureFn) == "function" then
                signature = signatureFn(uiState)
                if cached and cached.signature == signature then
                    useCachedValue = true
                end
            end

            local nextValue
            if useCachedValue then
                nextValue = cached.value
            else
                nextValue = tostring(compute(uiState) or "")
            end

            if currentValue ~= nextValue then
                uiState.set(alias, nextValue)
                changed = true
            end

            if derivedCache then
                derivedCache[alias] = {
                    signature = signature,
                    value = nextValue,
                }
            end
        end
    end

    return changed
end

--- Audits staged UI state against persisted config values and reloads staged values from config.
---@param name string Label used when printing mismatch diagnostics.
---@param uiState UiState UI state exposing config mismatch and reload helpers.
---@return table mismatches List of alias names whose staged values drifted from persisted config.
function host.auditAndResyncState(name, uiState)
    if not uiState or type(uiState.collectConfigMismatches) ~= "function" or type(uiState.reloadFromConfig) ~= "function" then
        return {}
    end

    local mismatches = uiState.collectConfigMismatches()
    if #mismatches > 0 then
        print("[" .. tostring(name) .. "] UI state drift detected; reloading staged values for: " .. table.concat(mismatches, ", "))
    end
    uiState.reloadFromConfig()
    return mismatches
end

--- Commits staged UI state back to config and reapplies live mutations when required.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore Managed module store associated with the definition.
---@param uiState UiState UI state exposing transactional flush and reload helpers.
---@return boolean ok True when the commit completed successfully.
---@return string|nil err Error message when the commit or rollback path fails.
function host.commitState(def, store, uiState)
    if not uiState or type(uiState.isDirty) ~= "function" or type(uiState.flushToConfig) ~= "function"
        or type(uiState.reloadFromConfig) ~= "function"
        or type(uiState._captureDirtyConfigSnapshot) ~= "function"
        or type(uiState._restoreConfigSnapshot) ~= "function" then
        return false, "uiState is missing transactional commit helpers"
    end

    if not uiState.isDirty() then
        return true, nil
    end

    local snapshot = uiState._captureDirtyConfigSnapshot()
    uiState.flushToConfig()

    local shouldReapply = public.mutation.mutatesRunData(def)
        and store
        and type(store.read) == "function"
        and store.read("Enabled") == true

    if not shouldReapply then
        return true, nil
    end

    local ok, err = public.mutation.reapply(def, store)
    if ok then
        return true, nil
    end

    uiState._restoreConfigSnapshot(snapshot)
    uiState.reloadFromConfig()

    local rollbackOk, rollbackErr = public.mutation.reapply(def, store)
    if not rollbackOk then
        if internal.logging and internal.logging.warn then
            internal.logging.warn("%s: uiState rollback reapply failed: %s",
                tostring(def.name or def.id or "module"),
                tostring(rollbackErr))
        end
        return false, tostring(err) .. " (rollback reapply failed: " .. tostring(rollbackErr) .. ")"
    end

    return false, err
end

--- Creates standalone window and menu-bar renderers for a module.
---@param def ModuleDefinition Module definition declaring UI and mutation behavior.
---@param store ManagedStore Managed module store associated with the definition.
---@param uiState UiState|nil Optional UI state override; defaults to `store.uiState`.
---@param opts StandaloneOpts|nil Optional standalone rendering hooks and window settings.
---@return StandaloneRuntime runtime Standalone runtime with `renderWindow` and `addMenuBar` callbacks.
function host.standaloneUI(def, store, uiState, opts)
    opts = opts or {}
    uiState = uiState or (store and store.uiState) or nil
    local DEFAULT_WINDOW_WIDTH = 960
    local DEFAULT_WINDOW_HEIGHT = 720

    local function getDrawTab()
        if type(opts.getDrawTab) == "function" then
            return opts.getDrawTab()
        end
        return opts.drawTab
    end

    local function onStateFlushed()
        if public.mutation.mutatesRunData(def) and store.read("Enabled") == true then
            rom.game.SetupRunData()
        end
    end

    local showWindow = false
    local didSeedWindowSize = false

    local function seedWindowSize(imgui)
        if didSeedWindowSize then
            return
        end
        imgui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
        didSeedWindowSize = true
    end

    local function renderWindow()
        if def.modpack and _coordinators[def.modpack] then return end
        if not showWindow then return end

        local imgui = rom.ImGui
        local title = (opts.windowTitle or def.name) .. "###" .. tostring(def.id)
        seedWindowSize(imgui)
        if imgui.Begin(title) then
            local enabled = store.read("Enabled") == true
            local enabledValue, enabledChanged = imgui.Checkbox("Enabled", enabled)
            if enabledChanged then
                local ok, err = public.mutation.setEnabled(def, store, enabledValue)
                if ok then
                    if public.mutation.mutatesRunData(def) then
                        rom.game.SetupRunData()
                    end
                else
                    if internal.logging and internal.logging.warn then
                        internal.logging.warn("%s %s failed: %s",
                            tostring(def.name or def.id or "module"),
                            enabledValue and "enable" or "disable",
                            tostring(err))
                    end
                end
            end

            local debugValue, debugChanged = imgui.Checkbox("Debug Mode", store.read("DebugMode") == true)
            if debugChanged then
                store.write("DebugMode", debugValue)
            end

            if uiState and imgui.Button("Audit + Resync UI State") then
                host.auditAndResyncState(def.name or def.id or "module", uiState)
            end

            local drawTab = getDrawTab()
            if drawTab then
                imgui.Separator()
                imgui.Spacing()
                drawTab(imgui, uiState)
                if uiState and uiState.isDirty() then
                    local ok = host.commitState(def, store, uiState)
                    if ok then
                        onStateFlushed()
                    end
                end
            end

            imgui.End()
        else
            showWindow = false
        end
    end

    local function addMenuBar()
        if def.modpack and _coordinators[def.modpack] then return end
        if rom.ImGui.BeginMenu(def.name) then
            if rom.ImGui.MenuItem(def.name) then
                showWindow = not showWindow
            end
            rom.ImGui.EndMenu()
        end
    end

    return {
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
    }
end
