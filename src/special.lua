local internal = AdamantModpackLib_Internal
local shared = internal.shared
local _coordinators = shared.coordinators

local function ClonePersistedValue(value)
    if type(value) == "table" then
        return rom.game.DeepCopyTable(value)
    end
    return value
end

local function BuildConfigEntries(rootNodes, configBackend)
    if not configBackend then
        return nil
    end
    local configEntries = {}
    for _, root in ipairs(rootNodes) do
        configEntries[root.alias] = configBackend.getEntry(root.configKey)
    end
    return configEntries
end

local function NormalizeNodeValue(node, value)
    local storageType = shared.StorageTypes[node.type]
    if storageType and type(storageType.normalize) == "function" then
        return storageType.normalize(node, value)
    end
    return value
end

local function ReadConfigValue(root, modConfig, configEntries)
    local entry = configEntries and configEntries[root.alias] or nil
    if entry then
        return entry:get()
    end
    return public.readPath(modConfig, root.configKey)
end

local function WriteConfigValue(root, modConfig, value, configEntries)
    local entry = configEntries and configEntries[root.alias] or nil
    if entry then
        entry:set(value)
        return
    end
    public.writePath(modConfig, root.configKey, value)
end

function shared.CreateUiState(modConfig, configBackend, storage)
    local persistedRootNodes = public.getStorageRoots(storage)
    local transientRootNodes = type(storage) == "table" and (rawget(storage, "_transientRootNodes") or {}) or {}
    local aliasNodes = public.getStorageAliases(storage)
    local staging = {}
    local dirty = false
    local dirtyRoots = {}
    local configEntries = BuildConfigEntries(persistedRootNodes, configBackend)

    local function syncPackedChildren(root, packedValue)
        for _, child in ipairs(root._bitAliases or {}) do
            local rawValue = public.readBitsValue(packedValue, child.offset, child.width)
            if child.type == "bool" then
                rawValue = rawValue ~= 0
            end
            staging[child.alias] = NormalizeNodeValue(child, rawValue)
        end
    end

    local function writeRootToStaging(root, value)
        local normalized = NormalizeNodeValue(root, value)
        staging[root.alias] = normalized
        if root.type == "packedInt" then
            syncPackedChildren(root, normalized)
        end
        if root._lifetime ~= "transient" then
            dirtyRoots[root.alias] = true
            dirty = true
        end
    end

    local function loadPersistedRootIntoStaging(root)
        local value = ReadConfigValue(root, modConfig, configEntries)
        if value == nil then
            value = ClonePersistedValue(root.default)
        end
        local normalized = NormalizeNodeValue(root, value)
        staging[root.alias] = normalized
        if root.type == "packedInt" then
            syncPackedChildren(root, normalized)
        end
    end

    local function loadTransientRootIntoStaging(root)
        local value = ClonePersistedValue(root.default)
        staging[root.alias] = NormalizeNodeValue(root, value)
    end

    local function copyConfigToStaging()
        for _, root in ipairs(persistedRootNodes) do
            loadPersistedRootIntoStaging(root)
        end
    end

    local function resetTransientToDefaults()
        for _, root in ipairs(transientRootNodes) do
            loadTransientRootIntoStaging(root)
        end
    end

    local function copyStagingToConfig()
        for _, root in ipairs(persistedRootNodes) do
            if dirtyRoots[root.alias] then
                WriteConfigValue(root, modConfig, staging[root.alias], configEntries)
            end
        end
    end

    local function captureDirtyConfigSnapshot()
        local snapshot = {}
        for _, root in ipairs(persistedRootNodes) do
            if dirtyRoots[root.alias] then
                table.insert(snapshot, {
                    root = root,
                    value = ClonePersistedValue(ReadConfigValue(root, modConfig, configEntries)),
                })
            end
        end
        return snapshot
    end

    local function restoreConfigSnapshot(snapshot)
        for _, entry in ipairs(snapshot or {}) do
            WriteConfigValue(entry.root, modConfig, ClonePersistedValue(entry.value), configEntries)
        end
    end

    local function clearDirty()
        dirty = false
        dirtyRoots = {}
    end

    local readonlyProxy = setmetatable({}, {
        __index = function(_, key)
            return staging[key]
        end,
        __newindex = function()
            error("uiState view is read-only; use state.set/update/toggle", 2)
        end,
        __pairs = function()
            return next, staging, nil
        end,
    })

    local function readStagingValue(alias)
        return staging[alias], aliasNodes[alias]
    end

    local function writeStagingValue(alias, value)
        local node = aliasNodes[alias]
        if not node then
            if shared.libWarn then
                shared.libWarn("uiState.set: unknown alias '%s'; value will not be persisted", tostring(alias))
            end
            return
        end

        if node._isBitAlias then
            local parent = node.parent
            local packedValue = staging[parent.alias]
            if packedValue == nil then
                if parent._lifetime == "transient" then
                    loadTransientRootIntoStaging(parent)
                else
                    loadPersistedRootIntoStaging(parent)
                end
                packedValue = staging[parent.alias]
            end
            local normalized = NormalizeNodeValue(node, value)
            local encoded = node.type == "bool" and (normalized and 1 or 0) or normalized
            local nextPacked = public.writeBitsValue(packedValue, node.offset, node.width, encoded)
            writeRootToStaging(parent, nextPacked)
            staging[node.alias] = normalized
            return
        end

        writeRootToStaging(node, value)
    end

    local function resetAliasValue(alias)
        local node = aliasNodes[alias]
        if not node then
            if shared.libWarn then
                shared.libWarn("uiState.reset: unknown alias '%s'; value will not be reset", tostring(alias))
            end
            return
        end

        local defaultValue = ClonePersistedValue(node.default)
        writeStagingValue(alias, defaultValue)
    end

    copyConfigToStaging()
    resetTransientToDefaults()
    clearDirty()

    local function snapshot()
        copyConfigToStaging()
        resetTransientToDefaults()
        clearDirty()
    end

    local function sync()
        copyStagingToConfig()
        clearDirty()
    end

    return {
        view = readonlyProxy,
        get = function(alias)
            return readStagingValue(alias)
        end,
        set = function(alias, value)
            writeStagingValue(alias, value)
        end,
        reset = function(alias)
            resetAliasValue(alias)
        end,
        update = function(alias, updater)
            local current = readStagingValue(alias)
            writeStagingValue(alias, updater(current))
        end,
        toggle = function(alias)
            local current = readStagingValue(alias)
            writeStagingValue(alias, not (current == true))
        end,
        reloadFromConfig = snapshot,
        flushToConfig = sync,
        _captureDirtyConfigSnapshot = captureDirtyConfigSnapshot,
        _restoreConfigSnapshot = restoreConfigSnapshot,
        isDirty = function()
            return dirty
        end,
        getAliasNode = function(alias)
            return aliasNodes[alias]
        end,
        collectConfigMismatches = function()
            local mismatches = {}
            for _, root in ipairs(persistedRootNodes) do
                local persistedValue = ReadConfigValue(root, modConfig, configEntries)
                if persistedValue == nil then
                    persistedValue = ClonePersistedValue(root.default)
                end
                persistedValue = NormalizeNodeValue(root, persistedValue)
                if not public.valuesEqual(root, persistedValue, staging[root.alias]) then
                    table.insert(mismatches, root.alias)
                end
                if root.type == "packedInt" then
                    for _, child in ipairs(root._bitAliases or {}) do
                        local childValue = public.readBitsValue(persistedValue, child.offset, child.width)
                        if child.type == "bool" then
                            childValue = childValue ~= 0
                        end
                        childValue = NormalizeNodeValue(child, childValue)
                        if not public.valuesEqual(child, childValue, staging[child.alias]) then
                            table.insert(mismatches, child.alias)
                        end
                    end
                end
            end
            return mismatches
        end,
    }
end

function public.runUiStatePass(opts)
    local draw = opts and opts.draw
    if type(draw) ~= "function" then
        return false
    end

    local uiState = opts.uiState
    if not uiState or type(uiState.isDirty) ~= "function" or type(uiState.flushToConfig) ~= "function" then
        if shared.libWarn then
            shared.libWarn("runUiStatePass: uiState is missing or malformed; pass skipped")
        end
        return false
    end
    local imgui = opts.imgui or rom.ImGui
    local beforeDraw = opts.beforeDraw
    if type(beforeDraw) == "function" then
        beforeDraw(imgui, uiState, opts.theme)
    end

    local drawChanged = draw(imgui, uiState, opts.theme) == true

    local afterDraw = opts.afterDraw
    if type(afterDraw) == "function" then
        afterDraw(imgui, uiState, opts.theme, drawChanged)
    end

    if uiState.isDirty() then
        if type(opts.commit) == "function" then
            local ok, err = opts.commit(uiState)
            if ok then
                if type(opts.onFlushed) == "function" then
                    opts.onFlushed()
                end
                return true, nil
            end
            if shared.libWarnAlways then
                shared.libWarnAlways("%s: uiState commit failed: %s",
                    tostring(opts.name or "uiState"),
                    tostring(err))
            end
            return false, err
        end

        uiState.flushToConfig()
        if type(opts.onFlushed) == "function" then
            opts.onFlushed()
        end
        return true
    end

    return false
end

function public.runDerivedText(uiState, entries, cache)
    if not uiState or type(uiState.set) ~= "function" or type(uiState.view) ~= "table" then
        if shared.libWarn then
            shared.libWarn("runDerivedText: uiState is missing or malformed; pass skipped")
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
            if shared.libWarn then
                shared.libWarn("runDerivedText: entries[%d].alias must be a non-empty string", index)
            end
        elseif type(compute) ~= "function" then
            if shared.libWarn then
                shared.libWarn("runDerivedText: entries[%d].compute must be a function", index)
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

function public.getCachedPreparedNode(cacheEntry, signature, buildFn, opts)
    if type(buildFn) ~= "function" then
        if shared.libWarn then
            shared.libWarn("getCachedPreparedNode: buildFn must be a function")
        end
        return nil, nil, false, nil
    end

    local cached = type(cacheEntry) == "table" and cacheEntry or nil
    local previousNode = cached and cached.node or nil
    if cached and previousNode ~= nil and cached.signature == signature then
        return cached, previousNode, false, previousNode
    end

    local node = buildFn(previousNode)
    if node == nil then
        return nil, nil, true, previousNode
    end

    if previousNode ~= nil and type(opts) == "table" and type(opts.reuseState) == "function" then
        opts.reuseState(node, previousNode)
    end

    return {
        signature = signature,
        node = node,
    }, node, true, previousNode
end

function public.auditAndResyncUiState(name, uiState)
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

function public.commitUiState(def, store, uiState)
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

    local shouldReapply = public.affectsRunData(def)
        and store
        and type(store.read) == "function"
        and store.read("Enabled") == true

    if not shouldReapply then
        return true, nil
    end

    local ok, err = public.reapplyDefinition(def, store)
    if ok then
        return true, nil
    end

    uiState._restoreConfigSnapshot(snapshot)
    uiState.reloadFromConfig()

    local rollbackOk, rollbackErr = public.reapplyDefinition(def, store)
    if not rollbackOk then
        if shared.libWarnAlways then
            shared.libWarnAlways("%s: uiState rollback reapply failed: %s",
                tostring(def.name or def.id or "module"),
                tostring(rollbackErr))
        end
        return false, tostring(err) .. " (rollback reapply failed: " .. tostring(rollbackErr) .. ")"
    end

    return false, err
end

function public.standaloneSpecialUI(def, store, uiState, opts)
    opts = opts or {}
    uiState = uiState or (store and store.uiState) or nil

    local function getDrawQuickContent()
        if type(opts.getDrawQuickContent) == "function" then
            return opts.getDrawQuickContent()
        end
        return opts.drawQuickContent
    end

    local function getBeforeDrawQuickContent()
        if type(opts.getBeforeDrawQuickContent) == "function" then
            return opts.getBeforeDrawQuickContent()
        end
        return opts.beforeDrawQuickContent
    end

    local function getAfterDrawQuickContent()
        if type(opts.getAfterDrawQuickContent) == "function" then
            return opts.getAfterDrawQuickContent()
        end
        return opts.afterDrawQuickContent
    end

    local function getDrawTab()
        if type(opts.getDrawTab) == "function" then
            return opts.getDrawTab()
        end
        return opts.drawTab
    end

    local function getBeforeDrawTab()
        if type(opts.getBeforeDrawTab) == "function" then
            return opts.getBeforeDrawTab()
        end
        return opts.beforeDrawTab
    end

    local function getAfterDrawTab()
        if type(opts.getAfterDrawTab) == "function" then
            return opts.getAfterDrawTab()
        end
        return opts.afterDrawTab
    end

    local function onStateFlushed()
        if public.affectsRunData(def) and store.read("Enabled") == true then
            rom.game.SetupRunData()
        end
    end

    local showWindow = false

    local function renderWindow()
        if def.modpack and _coordinators[def.modpack] then return end
        if not showWindow then return end

        local imgui = rom.ImGui
        local title = (opts.windowTitle or def.name) .. "###" .. tostring(def.id)
        if imgui.Begin(title) then
            local enabled = store.read("Enabled") == true
            local enabledValue, enabledChanged = imgui.Checkbox("Enabled", enabled)
            if enabledChanged then
                local ok, err = public.setDefinitionEnabled(def, store, enabledValue)
                if ok then
                    if public.affectsRunData(def) then
                        rom.game.SetupRunData()
                    end
                else
                    if shared.libWarnAlways then
                        shared.libWarnAlways("%s %s failed: %s",
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
                public.auditAndResyncUiState(def.name or def.id or "module", uiState)
            end

            local drawQuickContent = getDrawQuickContent()
            local beforeDrawQuickContent = getBeforeDrawQuickContent()
            local afterDrawQuickContent = getAfterDrawQuickContent()
            local drawTab = getDrawTab()
            local beforeDrawTab = getBeforeDrawTab()
            local afterDrawTab = getAfterDrawTab()
            if not drawTab and type(def.ui) == "table" and #def.ui > 0 then
                drawTab = function(ui)
                    public.drawUiTree(ui, def.ui, uiState, ui.GetWindowWidth() * 0.4, def.customTypes)
                end
            end

            if drawQuickContent or drawTab then
                imgui.Separator()
                imgui.Spacing()
            end

            if drawQuickContent then
                public.runUiStatePass({
                    name = def.name,
                    imgui = imgui,
                    uiState = uiState,
                    theme = opts.theme,
                    commit = function(state)
                        return public.commitUiState(def, store, state)
                    end,
                    beforeDraw = beforeDrawQuickContent,
                    draw = drawQuickContent,
                    afterDraw = afterDrawQuickContent,
                    onFlushed = onStateFlushed,
                })
            end

            if drawQuickContent and drawTab then
                imgui.Spacing()
                imgui.Separator()
            end

            if drawTab then
                public.runUiStatePass({
                    name = def.name,
                    imgui = imgui,
                    uiState = uiState,
                    theme = opts.theme,
                    commit = function(state)
                        return public.commitUiState(def, store, state)
                    end,
                    beforeDraw = beforeDrawTab,
                    draw = drawTab,
                    afterDraw = afterDrawTab,
                    onFlushed = onStateFlushed,
                })
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
