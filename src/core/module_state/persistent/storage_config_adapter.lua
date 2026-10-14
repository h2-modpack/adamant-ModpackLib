local deps = ...

local storage = deps.storage
local storageConfigAdapter = {}

local CONFIG_SECTION = "config"

---Config reads/writes for prepared storage roots over a native backend (file-backed, or
---memory-only when no config path resolved).
---@param backend table Backend from backend_factory.
---@param label string
function storageConfigAdapter.create(backend, label)
    local adapter = {}

    function adapter.withSaveBatch(callback)
        backend.reload()
        local diagnosticScope = backend.beginDiagnosticScope()
        backend.beginSaveBatch()
        local ok, err = pcall(callback)
        backend.endSaveBatch()
        backend.printDiagnosticScope(label, "hydrate", diagnosticScope)
        if not ok then
            error(err, 0)
        end
    end

    function adapter.reloadSource()
        backend.reload()
    end

    local function writeBackendTable(root, value)
        local rootKey = root._storageKey
        local cells = {}
        local rows = storage.table.ForEachNormalizedTableCell(root, value, function(rowIndex, cellRoot, cellValue)
            cells[#cells + 1] = {
                section = CONFIG_SECTION .. "." .. rootKey .. "." .. tostring(rowIndex),
                key = cellRoot._storageKey,
                value = cellValue,
            }
        end)
        local diagnosticScope = backend.beginDiagnosticScope()
        backend.writeTableCells(CONFIG_SECTION, rootKey, cells, #rows)
        backend.printDiagnosticScope(label, "writeTable:" .. rootKey, diagnosticScope)
    end

    function adapter.getEntry(alias)
        if backend.getEntry(CONFIG_SECTION, alias) then
            return {
                get = function()
                    return backend.read(CONFIG_SECTION, alias)
                end,
            }
        end
        return nil
    end

    function adapter.ensureValue(alias, value, root)
        if root.type == "table" then
            writeBackendTable(root, value)
            return true
        end
        backend.ensure(CONFIG_SECTION, alias, value)
        return true
    end

    function adapter.readValue(alias, root)
        if root.type == "table" then
            return backend.readTable(CONFIG_SECTION, root)
        end
        return backend.readBound(CONFIG_SECTION, alias, root.default)
    end

    function adapter.writeValue(alias, value, root)
        if root.type == "table" then
            writeBackendTable(root, value)
            return
        end
        local diagnosticScope = backend.beginDiagnosticScope()
        backend.write(CONFIG_SECTION, alias, value)
        backend.printDiagnosticScope(label, "write:" .. tostring(alias), diagnosticScope)
    end

    return adapter
end

return storageConfigAdapter
