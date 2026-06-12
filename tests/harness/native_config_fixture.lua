local fixture = {}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = deepCopy(child)
    end
    return copy
end

local function formatConfigValue(value)
    if type(value) == "boolean" then
        return value and "true" or "false"
    elseif type(value) == "number" then
        return tostring(value)
    end
    value = tostring(value or "")
    value = string.gsub(value, "\\", "\\\\")
    value = string.gsub(value, '"', '\\"')
    value = string.gsub(value, "\n", "\\n")
    return '"' .. value .. '"'
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function unescapeString(value)
    value = string.gsub(value, "\\n", "\n")
    value = string.gsub(value, '\\"', '"')
    value = string.gsub(value, "\\\\", "\\")
    return value
end

local function parseConfigValue(rawValue)
    rawValue = trim(rawValue)
    if rawValue == "" then
        return ""
    end

    local first = string.sub(rawValue, 1, 1)
    local last = string.sub(rawValue, -1)
    if first == '"' and last == '"' and #rawValue >= 2 then
        return unescapeString(string.sub(rawValue, 2, -2))
    end

    local lower = string.lower(rawValue)
    if lower == "true" then
        return true
    elseif lower == "false" then
        return false
    end

    local numberValue = tonumber(rawValue)
    if numberValue ~= nil then
        return numberValue
    end

    return rawValue
end

local function applyRowCount(values, tableKey, rawCount)
    local rowCount = tonumber(rawCount) or 0
    local rows = values[tableKey] or {}
    values[tableKey] = rows
    for rowIndex = 1, rowCount do
        rows[rowIndex] = rows[rowIndex] or {}
    end
end

local function tableRowCount(rows)
    local rowCount = #rows
    local explicitRowCount = tonumber(rawget(rows, "_RowCount"))
    if explicitRowCount ~= nil and explicitRowCount > rowCount then
        return explicitRowCount
    end
    return rowCount
end

function fixture.combinePath(left, right)
    if string.sub(left, -1) == "/" then
        return left .. right
    end
    return left .. "/" .. right
end

function fixture.configureRoot(rom, root)
    os.execute('mkdir -p "' .. root .. '"')
    rom.paths = rom.paths or {}
    rom.path = rom.path or {}
    rom.paths.config = function()
        return root
    end
    rom.path.combine = fixture.combinePath
end

function fixture.write(root, pluginGuid, values)
    local file = assert(io.open(fixture.combinePath(root, pluginGuid .. ".cfg"), "w"))
    file:write("## Settings file was created by plugin adamant-ModpackLib test harness\n\n")
    file:write("[config]\n\n")
    for key, value in pairs(values or {}) do
        if type(value) ~= "table" then
            file:write(tostring(key), " = ", formatConfigValue(value), "\n")
        end
    end
    for key, value in pairs(values or {}) do
        if type(value) == "table" then
            file:write("\n[config.", tostring(key), "]\n\n")
            file:write("_RowCount = ", tostring(tableRowCount(value)), "\n")
            for rowIndex, row in ipairs(value) do
                file:write("\n[config.", tostring(key), ".", tostring(rowIndex), "]\n\n")
                for cellKey, cellValue in pairs(row or {}) do
                    if cellKey ~= "_RowCount" and type(cellValue) ~= "table" then
                        file:write(tostring(cellKey), " = ", formatConfigValue(cellValue), "\n")
                    end
                end
            end
        end
    end
    file:close()
end

function fixture.read(path)
    local result = {}
    local file = io.open(path, "r")
    if not file then
        return result
    end

    local currentSection = "config"
    for line in file:lines() do
        local section = string.match(line, "^%s*%[([^%]]+)%]%s*$")
        if section then
            currentSection = trim(section)
        elseif not string.match(line, "^%s*[#;]") then
            local key, rawValue = string.match(line, "^%s*([^=]-)%s*=%s*(.-)%s*$")
            key = key and trim(key) or nil
            if key and key ~= "" then
                local value = parseConfigValue(rawValue)
                if currentSection == "config" then
                    local tableKey = string.match(key, "^(.+)%.%_RowCount$")
                    if tableKey then
                        applyRowCount(result, tableKey, value)
                    else
                        result[key] = value
                    end
                else
                    local tableKey, rowIndex = string.match(currentSection, "^config%.([^%.]+)%.(%d+)$")
                    if tableKey then
                        rowIndex = tonumber(rowIndex)
                        result[tableKey] = result[tableKey] or {}
                        result[tableKey][rowIndex] = result[tableKey][rowIndex] or {}
                        result[tableKey][rowIndex][key] = value
                    else
                        tableKey = string.match(currentSection, "^config%.([^%.]+)$")
                        if tableKey and key == "_RowCount" then
                            applyRowCount(result, tableKey, value)
                        end
                    end
                end
            end
        end
    end
    file:close()

    return result
end

function fixture.installProxy(config, path)
    if type(config) ~= "table" then
        return
    end

    local snapshot = deepCopy(config)
    for key in pairs(config) do
        config[key] = nil
    end

    local function writeSnapshot(snapshotValue)
        local dir, fileName = string.match(path, "^(.*)/([^/]+)$")
        local pluginGuid = fileName and string.gsub(fileName, "%.cfg$", "") or "test-module"
        fixture.write(dir or ".", pluginGuid, snapshotValue)
    end

    setmetatable(config, {
        __index = function(_, key)
            return fixture.read(path)[key]
        end,
        __newindex = function(_, key, value)
            local current = fixture.read(path)
            current[key] = value
            writeSnapshot(current)
        end,
        __pairs = function()
            return pairs(fixture.read(path))
        end,
        __len = function()
            return #fixture.read(path)
        end,
    })
    writeSnapshot(snapshot)
end

function fixture.create(root, config, pluginGuid)
    config = config or {}
    pluginGuid = pluginGuid or ("test-module-state-" .. tostring(os.clock()):gsub("[^%d]", ""))
    local path = fixture.combinePath(root, pluginGuid .. ".cfg")
    fixture.write(root, pluginGuid, config)
    fixture.installProxy(config, path)
    return path
end

return fixture
