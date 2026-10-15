-- Reserved hotkey sources: the Hell2Modding overlay key read from its hotkey config file, and the
-- manual list kept in Lib config. This file owns both external translation boundaries.

local deps = ...

local rom = deps.rom
local bindings = deps.bindings

local reserved = {}

reserved.HELL2MODDING_CONFIG_FILE = "Hell2Modding-Hell2Modding-Hotkeys.cfg"
reserved.HELL2MODDING_REASON = "Hell2Modding overlay"
reserved.MANUAL_REASON = "Lib settings"

local function trim(text)
    return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

---Extracts the raw `gui_toggle` value from Hell2Modding's hotkey config text (TOML). Only the
---`gui_toggle = '<value>'` assignment is read; quoted and bare values are accepted.
---@param text string
---@return string? raw
function reserved.parseGuiToggle(text)
    for line in string.gmatch(text, "[^\r\n]+") do
        local rest = string.match(line, "^%s*gui_toggle%s*=%s*(.-)%s*$")
        if rest ~= nil then
            local quoted = string.match(rest, "^'([^']*)'") or string.match(rest, '^"([^"]*)"')
            if quoted ~= nil then
                return quoted
            end
            local bare = string.match(rest, "^([^%s#]+)")
            return bare
        end
    end
    return nil
end

---Maps a Hell2Modding virtual-key name to a binding Lib can express (`VK_F1`..`VK_F12` -> `F1`..`F12`).
---@param raw string
---@return string? binding
function reserved.mapVirtualKey(raw)
    local number = tonumber(string.match(raw, "^VK_F(%d+)$"))
    if number ~= nil and bindings.KEYS[number] ~= nil and raw == "VK_F" .. number then
        return bindings.KEYS[number]
    end
    return nil
end

local function resolveConfigPath()
    if type(rom.paths) ~= "table" or type(rom.paths.config) ~= "function"
        or type(rom.path) ~= "table" or type(rom.path.combine) ~= "function" then
        return nil
    end
    local okRoot, root = pcall(rom.paths.config)
    if not okRoot or type(root) ~= "string" or root == "" then
        return nil
    end
    local okPath, path = pcall(rom.path.combine, root, reserved.HELL2MODDING_CONFIG_FILE)
    if okPath and type(path) == "string" and path ~= "" then
        return path
    end
    return nil
end

---@class AdamantModpackLib.HotkeyDetectedReserve
---@field raw string Value read from `gui_toggle`, such as "VK_F1".
---@field binding string? Mapped binding, or nil when Lib cannot express the key.

---Reads Hell2Modding's overlay key from `<config folder>/Hell2Modding-Hell2Modding-Hotkeys.cfg`, the
---same ReturnOfModding config folder module `.cfg` files live in. A missing file, or a file without
---`gui_toggle`, means nothing detected.
---@return AdamantModpackLib.HotkeyDetectedReserve?
function reserved.detectHell2Modding()
    local path = resolveConfigPath()
    if path == nil then
        return nil
    end
    local file = io.open(path, "r")
    if file == nil then
        return nil
    end
    local text = file:read("*a")
    file:close()
    local raw = type(text) == "string" and reserved.parseGuiToggle(text) or nil
    if raw == nil or raw == "" then
        return nil
    end
    return {
        raw = raw,
        binding = reserved.mapVirtualKey(raw),
    }
end

---Parses the Lib config manual list: comma-separated bindings. Blank entries are dropped; entries
---are trimmed but otherwise kept verbatim, so invalid text stays visible in the editor.
---@param text any
---@return string[]
function reserved.parseManualList(text)
    local list = {}
    if type(text) ~= "string" then
        return list
    end
    for entry in string.gmatch(text, "[^,]+") do
        entry = trim(entry)
        if entry ~= "" then
            list[#list + 1] = entry
        end
    end
    return list
end

---@param list string[]
---@return string
function reserved.formatManualList(list)
    return table.concat(list, ",")
end

---Builds the reserved binding map (binding -> reason) from both sources. Manual entries that are not
---valid bindings are ignored here.
---@param detected AdamantModpackLib.HotkeyDetectedReserve?
---@param manualList string[]
---@return table<string, string>
-- Every modifier prefix a binding can carry, including Ctrl+Shift+Alt.
local ALL_PREFIXES = { "Ctrl+Shift+Alt+" }
for _, choice in ipairs(bindings.MODIFIER_CHOICES) do
    ALL_PREFIXES[#ALL_PREFIXES + 1] = choice.prefix
end

-- A reserved entry without modifiers reserves its key under every modifier combination: tools
-- such as Hell2Modding match a single key and fire regardless of held modifiers. An entry with
-- modifiers reserves exactly that combination.
local function reserveEntry(map, entry, reason)
    local parsed = bindings.parse(entry)
    if parsed == nil then
        return
    end
    if parsed.prefix ~= "" then
        map[parsed.binding] = map[parsed.binding] or reason
        return
    end
    for _, prefix in ipairs(ALL_PREFIXES) do
        local binding = prefix .. parsed.key
        map[binding] = map[binding] or reason
    end
end

function reserved.buildMap(detected, manualList)
    local map = {}
    if detected ~= nil and detected.binding ~= nil then
        reserveEntry(map, detected.binding, reserved.HELL2MODDING_REASON)
    end
    for _, entry in ipairs(manualList) do
        reserveEntry(map, entry, reserved.MANUAL_REASON)
    end
    return map
end

return reserved
