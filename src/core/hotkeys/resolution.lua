-- Pure hotkey ownership resolution.
--
-- Inputs are already in tie-break order (pack module order, plugin GUID, declaration order), so the
-- first candidate for a key wins when no recorded owner is still a candidate. The recorded owner
-- (`history`) keeps its key while it remains a candidate.

local deps = ...

local bindings = deps.bindings

local resolution = {}

---@class AdamantModpackLib.HotkeyResolutionInput
---@field key string Request identity (owner + request id); stable across module reloads.
---@field binding string Committed binding string.
---@field enabled boolean Whether the requesting module is enabled.

---@class AdamantModpackLib.HotkeyResolution
---@field state "active"|"conflict"|"reserved"|"unbound"|"invalid"|"disabled"
---@field ownerIndex integer? Conflict only: index of the owning input.
---@field reservedBy string? Reserved only: reason from the reserved map.

---Resolves every input's state. Mutates `history` (binding -> request key): a key's owner is
---recorded when it is chosen, and the record is cleared once nobody is a candidate for that binding.
---@param inputs AdamantModpackLib.HotkeyResolutionInput[] In tie-break order.
---@param history table<string, string>
---@param reserved table<string, string> Reserved binding -> reason.
---@return AdamantModpackLib.HotkeyResolution[] results Parallel to `inputs`.
function resolution.resolve(inputs, history, reserved)
    local results = {}
    local candidatesByBinding = {}
    local bindingOrder = {}

    for index, input in ipairs(inputs) do
        local binding = input.binding
        if binding == bindings.UNBOUND then
            results[index] = { state = "unbound" }
        elseif bindings.parse(binding) == nil then
            results[index] = { state = "invalid" }
        elseif reserved[binding] ~= nil then
            results[index] = { state = "reserved", reservedBy = reserved[binding] }
        elseif not input.enabled then
            results[index] = { state = "disabled" }
        else
            local candidates = candidatesByBinding[binding]
            if candidates == nil then
                candidates = {}
                candidatesByBinding[binding] = candidates
                bindingOrder[#bindingOrder + 1] = binding
            end
            candidates[#candidates + 1] = index
        end
    end

    for _, binding in ipairs(bindingOrder) do
        local candidates = candidatesByBinding[binding]
        local ownerIndex = candidates[1]
        local recordedKey = history[binding]
        for _, index in ipairs(candidates) do
            if inputs[index].key == recordedKey then
                ownerIndex = index
                break
            end
        end
        history[binding] = inputs[ownerIndex].key
        for _, index in ipairs(candidates) do
            if index == ownerIndex then
                results[index] = { state = "active" }
            else
                results[index] = { state = "conflict", ownerIndex = ownerIndex }
            end
        end
    end

    for binding in pairs(history) do
        if candidatesByBinding[binding] == nil then
            history[binding] = nil
        end
    end

    return results
end

return resolution
