local deps = ...

local storage = deps and deps.storage or nil
local storageConfigAdapter = {}

local CONFIG_SECTION = "config"

local function isTableRoot(root)
    return type(root) == "table" and root.type == "table"
end

local function getStorageKey(root)
    return type(root) == "table" and (root._storageKey or root.alias) or nil
end

function storageConfigAdapter.create(backend, label)
    local adapter = {}
    local fallbackConfig = {}

    local function beginBackendDiagnosticScope()
        if backend and type(backend.beginDiagnosticScope) == "function" then
            return backend.beginDiagnosticScope()
        end
        return nil
    end

    local function printBackendDiagnosticScope(phase, scope)
        if backend and type(backend.printDiagnosticScope) == "function" then
            backend.printDiagnosticScope(label, phase, scope)
        end
    end

    function adapter.withSaveBatch(callback)
        if backend and type(backend.reload) == "function" then
            backend.reload()
        end
        if backend and type(backend.beginSaveBatch) == "function"
            and type(backend.endSaveBatch) == "function" then
            local diagnosticScope = beginBackendDiagnosticScope()
            backend.beginSaveBatch()
            local ok, err = pcall(callback)
            backend.endSaveBatch()
            printBackendDiagnosticScope("hydrate", diagnosticScope)
            if not ok then
                error(err, 0)
            end
            return
        end
        callback()
    end

    function adapter.reloadSource()
        if backend and type(backend.reload) == "function" then
            backend.reload()
        end
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
        local diagnosticScope = beginBackendDiagnosticScope()
        local ok = backend.writeTableCells(CONFIG_SECTION, rootKey, cells, #rows)
        printBackendDiagnosticScope("writeTable:" .. rootKey, diagnosticScope)
        return ok
    end

    function adapter.getEntry(alias)
        if backend then
            local entry = backend.getEntry(CONFIG_SECTION, alias)
            if entry then
                return {
                    get = function()
                        return backend.read(CONFIG_SECTION, alias)
                    end,
                }
            end
        end
        return nil
    end

    function adapter.ensureValue(alias, value, root)
        if isTableRoot(root) and writeBackendTable(root, value) then
            return true
        end
        if backend then
            local ok = backend.ensure(CONFIG_SECTION, alias, value)
            if ok then
                return true
            end
        end
        if fallbackConfig[alias] == nil then
            fallbackConfig[alias] = value
        end
        return true
    end

    function adapter.readValue(alias, root)
        local raw
        local backendRaw
        if backend then
            if isTableRoot(root) and type(backend.readTable) == "function" then
                backendRaw = backend.readTable(CONFIG_SECTION, root)
            elseif type(backend.readBound) == "function" and root ~= nil then
                backendRaw = backend.readBound(CONFIG_SECTION, alias, root.default)
            else
                backendRaw = backend.read(CONFIG_SECTION, alias)
            end
            raw = backendRaw
        end
        if raw == nil then
            raw = fallbackConfig[alias]
        end
        return raw
    end

    function adapter.writeValue(alias, value, root)
        if isTableRoot(root) and writeBackendTable(root, value) then
            return true
        end
        if backend then
            local diagnosticScope = beginBackendDiagnosticScope()
            local ok = backend.write(CONFIG_SECTION, alias, value)
            printBackendDiagnosticScope("write:" .. tostring(alias), diagnosticScope)
            if ok then
                return true
            end
        end
        fallbackConfig[alias] = value
        return true
    end

    return adapter
end

return storageConfigAdapter
