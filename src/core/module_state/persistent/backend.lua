local deps = ...

local chalk = deps.chalk
local backendCache = setmetatable({}, { __mode = "k" })

local function create(config)
    if not chalk then
        return nil
    end

    local ok, rawConfig = pcall(chalk.original, config)
    if not ok or type(rawConfig) ~= "table" or type(rawConfig.entries) ~= "table" then
        return nil
    end

    local backend = backendCache[rawConfig]
    if backend then
        return backend
    end

    local entryIndex = {}
    for descriptor, entry in pairs(rawConfig.entries) do
        local section = descriptor.section
        local key = descriptor.key
        if section ~= nil and key ~= nil then
            local sectionEntries = entryIndex[section]
            if not sectionEntries then
                sectionEntries = {}
                entryIndex[section] = sectionEntries
            end
            sectionEntries[key] = entry
        end
    end

    local pathEntryCache = {}
    backend = {}

    local function makeCacheKey(section, key)
        return tostring(section) .. "\0" .. tostring(key)
    end

    function backend.getEntry(section, key)
        local cacheKey = makeCacheKey(section, key)
        local cached = pathEntryCache[cacheKey]
        if cached ~= nil then
            return cached or nil
        end

        local sectionEntries = entryIndex[section]
        local entry = sectionEntries and sectionEntries[key] or nil
        if entry then
            pathEntryCache[cacheKey] = entry
            return entry
        end

        pathEntryCache[cacheKey] = false
        return nil
    end

    function backend.ensure(section, key, value)
        local entry = backend.getEntry(section, key)
        if entry then
            return true
        end

        if type(section) ~= "string" or section == "" or type(key) ~= "string" or key == ""
            or type(rawConfig.bind) ~= "function" then
            return false
        end

        entry = rawConfig:bind(section, key, value, "")
        if not entry then
            return false
        end

        local sectionEntries = entryIndex[section]
        if not sectionEntries then
            sectionEntries = {}
            entryIndex[section] = sectionEntries
        end
        sectionEntries[key] = entry
        pathEntryCache[makeCacheKey(section, key)] = entry

        if type(rawConfig.save) == "function" then
            rawConfig:save()
        end
        return true
    end

    function backend.read(section, key)
        local entry = backend.getEntry(section, key)
        if entry then
            return entry:get()
        end
        return nil
    end

    function backend.write(section, key, value)
        local entry = backend.getEntry(section, key)
        if entry then
            entry:set(value)
            if type(rawConfig.save) == "function" then
                rawConfig:save()
            end
            return true
        end
        return false
    end

    function backend.clear(section, key)
        local entry = backend.getEntry(section, key)
        if entry then
            entry:set(nil)
            if type(rawConfig.save) == "function" then
                rawConfig:save()
            end
            return true
        end
        return false
    end

    backend.rawConfig = rawConfig
    backendCache[rawConfig] = backend
    return backend
end

return {
    create = create,
}
