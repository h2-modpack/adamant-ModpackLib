local deps = ...

local logging = deps.logging

---Module identity and logging surface shared by the declaration facade (from raw
---create opts, before a definition exists) and the managed module (from the
---prepared definition, whose identity fields are copies of those opts).
---@param fields { id: string?, modpack: string?, name: string?, shortName: string?, tooltip: string?, hash: boolean? }
---@param pluginGuid string
---@param isDebugEnabled fun(): boolean
---@return table identity `getOwnerId`, `getModuleId`, `getPackId`, `getMeta`, `log`, `logIf`
local function create(fields, pluginGuid, isDebugEnabled)
    local logPrefix = "[" .. tostring(fields.id or pluginGuid) .. "] "
    return {
        getOwnerId = function()
            return pluginGuid
        end,
        getModuleId = function()
            return fields.id
        end,
        getPackId = function()
            return fields.modpack
        end,
        getMeta = function()
            return {
                name = fields.name,
                shortName = fields.shortName,
                tooltip = fields.tooltip,
                hash = fields.hash,
            }
        end,
        log = function(fmt, ...)
            logging.printWithPrefix(logPrefix, fmt, ...)
        end,
        logIf = function(fmt, ...)
            logging.printWithPrefixIf(isDebugEnabled(), logPrefix, fmt, ...)
        end,
    }
end

return {
    create = create,
}
