-- Widget refs for Lib-drawn hotkey rows (module header blocks and the overview).
--
-- A row ref reads the owning live module's committed binding and writes through its staged state
-- and commit (`writeAndFlush`), the same path the modpack window uses for module enabled state.
-- Refs are cached by request identity; a module reload installs new request objects, so stale
-- refs fall out of the weak table.

local deps = ...

local logging = deps.logging
local hotkeys = deps.hotkeys
local getLiveModule = deps.getLiveModule

local refs = setmetatable({}, { __mode = "k" })

local function createRowField(ownerId, alias, label)
    return {
        read = function()
            local liveModule = getLiveModule(ownerId)
            if liveModule == nil then
                return ""
            end
            return liveModule.read(alias)
        end,
        write = function(_, value)
            local liveModule = getLiveModule(ownerId)
            if liveModule == nil then
                return false
            end
            local ok, err = liveModule.writeAndFlush(alias, value)
            if not ok then
                logging.violate("hotkeys.commit_failed", "%s hotkey '%s' commit failed: %s",
                    tostring(ownerId), tostring(label), tostring(err))
            end
            return ok
        end,
    }
end

---@param row AdamantModpackLib.HotkeyRow
---@return AdamantModpackLib.HotkeyRef
return function(row)
    local ref = refs[row.request]
    if ref == nil then
        ref = hotkeys.createRef(createRowField(row.ownerId, row.alias, row.label), row.ownerId, row.request)
        refs[row.request] = ref
    end
    return ref
end
