local storageConfigAdapter = {}

local CONFIG_SECTION = "config"

function storageConfigAdapter.create(modConfig, backend)
    local adapter = {}

    function adapter.getEntry(alias)
        if backend then
            return backend.getEntry(CONFIG_SECTION, alias)
        end
        return nil
    end

    function adapter.ensureValue(alias, value)
        if backend then
            return backend.ensure(CONFIG_SECTION, alias, value)
        end
        if modConfig[alias] == nil then
            modConfig[alias] = value
        end
        return true
    end

    function adapter.readValue(alias)
        local raw
        if backend then
            raw = backend.read(CONFIG_SECTION, alias)
        end
        if raw == nil then
            raw = modConfig[alias]
        end
        return raw
    end

    function adapter.writeValue(alias, value)
        if backend and backend.write(CONFIG_SECTION, alias, value) then
            return true
        end
        modConfig[alias] = value
        return true
    end

    return adapter
end

return storageConfigAdapter
