-- Pure hotkey binding grammar.
--
-- A binding is "" (unbound) or `[Ctrl+][Shift+][Alt+]<Key>` with the modifiers in that canonical
-- order and `<Key>` one of F1-F12. Anything else is invalid. Parse results are memoized by string so
-- per-frame callers (the widget, the tick) never allocate.

local bindings = {}

bindings.UNBOUND = ""

---@type string[]
bindings.KEYS = {}
local keyIndex = {}
for number = 1, 12 do
    local key = "F" .. number
    bindings.KEYS[number] = key
    keyIndex[key] = number
end

-- Modifier dropdown choices, in display order. `prefix` is the canonical binding prefix.
---@type { label: string, prefix: string, ctrl: boolean, shift: boolean, alt: boolean }[]
bindings.MODIFIER_CHOICES = {
    { label = "None", prefix = "", ctrl = false, shift = false, alt = false },
    { label = "Ctrl", prefix = "Ctrl+", ctrl = true, shift = false, alt = false },
    { label = "Shift", prefix = "Shift+", ctrl = false, shift = true, alt = false },
    { label = "Alt", prefix = "Alt+", ctrl = false, shift = false, alt = true },
    { label = "Ctrl+Shift", prefix = "Ctrl+Shift+", ctrl = true, shift = true, alt = false },
    { label = "Ctrl+Alt", prefix = "Ctrl+Alt+", ctrl = true, shift = false, alt = true },
    { label = "Shift+Alt", prefix = "Shift+Alt+", ctrl = false, shift = true, alt = true },
}

local MODIFIER_ORDER = { "Ctrl", "Shift", "Alt" }

local function modifierPrefix(ctrl, shift, alt)
    return (ctrl and "Ctrl+" or "") .. (shift and "Shift+" or "") .. (alt and "Alt+" or "")
end

---@class AdamantModpackLib.HotkeyBinding
---@field binding string Canonical binding string.
---@field key string F1-F12.
---@field keyIndex integer Index into `bindings.KEYS`.
---@field ctrl boolean
---@field shift boolean
---@field alt boolean
---@field prefix string Canonical modifier prefix, such as "Ctrl+Shift+".
---@field modifierIndex integer? Index into `bindings.MODIFIER_CHOICES`; nil for Ctrl+Shift+Alt.

local parsedCache = {}
local INVALID = {}

local function parseUncached(text)
    local tokens = {}
    for token in string.gmatch(text, "[^+]+") do
        tokens[#tokens + 1] = token
    end
    -- Rejects empty segments such as "Ctrl++F5" or a trailing "+".
    if #tokens == 0 or table.concat(tokens, "+") ~= text then
        return nil
    end

    local key = tokens[#tokens]
    if keyIndex[key] == nil then
        return nil
    end

    local held = {}
    local nextModifier = 1
    for index = 1, #tokens - 1 do
        local token = tokens[index]
        local matched = false
        while nextModifier <= #MODIFIER_ORDER do
            local modifier = MODIFIER_ORDER[nextModifier]
            nextModifier = nextModifier + 1
            if modifier == token then
                held[modifier] = true
                matched = true
                break
            end
        end
        if not matched then
            return nil
        end
    end

    local ctrl, shift, alt = held.Ctrl == true, held.Shift == true, held.Alt == true
    local prefix = modifierPrefix(ctrl, shift, alt)
    local modifierIndex = nil
    for index, choice in ipairs(bindings.MODIFIER_CHOICES) do
        if choice.prefix == prefix then
            modifierIndex = index
            break
        end
    end
    return {
        binding = text,
        key = key,
        keyIndex = keyIndex[key],
        ctrl = ctrl,
        shift = shift,
        alt = alt,
        prefix = prefix,
        modifierIndex = modifierIndex,
    }
end

---Parses a canonical binding. Returns nil for "" (unbound) and for invalid text; use
---`bindings.isValid` to tell the two apart.
---@param text any
---@return AdamantModpackLib.HotkeyBinding?
function bindings.parse(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local cached = parsedCache[text]
    if cached == nil then
        cached = parseUncached(text) or INVALID
        parsedCache[text] = cached
    end
    if cached == INVALID then
        return nil
    end
    return cached
end

---True for "" and for every canonical binding.
---@param text any
---@return boolean
function bindings.isValid(text)
    return text == bindings.UNBOUND or bindings.parse(text) ~= nil
end

---Combines a modifier prefix (from `MODIFIER_CHOICES`) and a key into a canonical binding.
---A nil or empty key yields "" (unbound).
---@param prefix string?
---@param key string?
---@return string
function bindings.format(prefix, key)
    if key == nil or key == "" then
        return bindings.UNBOUND
    end
    return (prefix or "") .. key
end

return bindings
