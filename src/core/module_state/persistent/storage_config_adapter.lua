local deps = ...

local storage = deps and deps.storage or nil
local storageConfigAdapter = {}

local CONFIG_SECTION = "config"

local function shouldDebugAlias(alias)
    return rawget(_G, "AdamantEnableToggleDebug") == true
        and (alias == "Enabled" or alias == "DebugMode" or alias == "AdamantFramework_PackRestoreSnapshot")
end

local function isTableRoot(root)
    return type(root) == "table" and root.type == "table"
end

local function getStorageKey(root)
    return type(root) == "table" and (root._storageKey or root.alias) or nil
end

function storageConfigAdapter.create(modConfig, backend, label)
    local adapter = {}

    function adapter.withSaveBatch(callback)
        if backend and type(backend.beginSaveBatch) == "function"
            and type(backend.endSaveBatch) == "function" then
            backend.beginSaveBatch()
            local ok, err = pcall(callback)
            backend.endSaveBatch()
            if not ok then
                error(err, 0)
            end
            return
        end
        callback()
    end

    local function writeBackendTable(root, value)
        if not backend or type(backend.writeTableCells) ~= "function"
            or not storage or not storage.table
            or type(storage.table.ForEachNormalizedTableCell) ~= "function" then
            return false
        end

        local rootKey = getStorageKey(root)
        if type(rootKey) ~= "string" or rootKey == "" then
            return false
        end

        local cells = {}
        local rows = storage.table.ForEachNormalizedTableCell(root, value, function(rowIndex, cellRoot, cellValue)
            local cellKey = getStorageKey(cellRoot)
            cells[#cells + 1] = {
                section = CONFIG_SECTION .. "." .. rootKey .. "." .. tostring(rowIndex),
                key = cellKey,
                value = cellValue,
            }
        end)
        return backend.writeTableCells(CONFIG_SECTION, rootKey, cells, #rows)
    end

    function adapter.getEntry(alias)
        if backend then
            return backend.getEntry(CONFIG_SECTION, alias)
        end
        return nil
    end

    function adapter.ensureValue(alias, value, root)
        if isTableRoot(root) and writeBackendTable(root, value) then
            if rawget(_G, "AdamantEnableToggleDebug") == true then
                print(string.format("[lib-debug] storage ensure alias=%s value=%s backend=%s ok=true",
                    tostring(alias), tostring(value), tostring(true)))
            end
            return true
        end
        if backend then
            local ok = backend.ensure(CONFIG_SECTION, alias, value)
            if rawget(_G, "AdamantEnableToggleDebug") == true then
                print(string.format("[lib-debug] storage ensure alias=%s value=%s backend=%s ok=%s",
                    tostring(alias), tostring(value), tostring(true), tostring(ok)))
            end
            if ok then
                return true
            end
        end
        if modConfig[alias] == nil then
            modConfig[alias] = value
        end
        if rawget(_G, "AdamantEnableToggleDebug") == true then
            print(string.format("[lib-debug] storage ensure alias=%s value=%s backend=%s ok=true",
                tostring(alias), tostring(value), tostring(false)))
        end
        return true
    end

    function adapter.readValue(alias, root)
        local raw
        local backendRaw
        if backend then
            if isTableRoot(root) and type(backend.readTable) == "function" then
                backendRaw = backend.readTable(CONFIG_SECTION, root)
            else
                backendRaw = backend.read(CONFIG_SECTION, alias)
            end
            raw = backendRaw
        end
        local fallbackRaw
        if raw == nil then
            fallbackRaw = modConfig[alias]
            raw = fallbackRaw
        elseif shouldDebugAlias(alias) then
            fallbackRaw = modConfig[alias]
        end
        if shouldDebugAlias(alias) then
            print(string.format(
                "[lib-debug] storage read module=%s alias=%s backend_present=%s backend_raw=%s fallback_raw=%s final=%s",
                tostring(label or "module"),
                tostring(alias),
                tostring(backend ~= nil),
                tostring(backendRaw),
                tostring(fallbackRaw),
                tostring(raw)))
        end
        return raw
    end

    function adapter.writeValue(alias, value, root)
        if isTableRoot(root) and writeBackendTable(root, value) then
            if rawget(_G, "AdamantEnableToggleDebug") == true then
                print(string.format("[lib-debug] storage write alias=%s value=%s backend=%s ok=true",
                    tostring(alias), tostring(value), tostring(true)))
            end
            return true
        end
        if backend and backend.write(CONFIG_SECTION, alias, value) then
            if rawget(_G, "AdamantEnableToggleDebug") == true then
                print(string.format("[lib-debug] storage write alias=%s value=%s backend=%s ok=true",
                    tostring(alias), tostring(value), tostring(true)))
            end
            return true
        end
        modConfig[alias] = value
        if rawget(_G, "AdamantEnableToggleDebug") == true then
            print(string.format("[lib-debug] storage write alias=%s value=%s backend=%s ok=true",
                tostring(alias), tostring(value), tostring(false)))
        end
        return true
    end

    return adapter
end

return storageConfigAdapter
