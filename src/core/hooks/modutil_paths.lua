local deps = ...

-- Translation boundary for ModUtil path APIs.
local logging = deps.logging
local modutil = deps.modutil

local modutilPaths = {}

local function getModUtilRuntime()
    local globals = modutil and modutil.globals
    local runtime = globals and globals.ModUtil
    if not (runtime and runtime.Path) then
        logging.violate("hooks.modutil_unavailable", "hooks: SGG_Modding-ModUtil is not available")
    end
    return runtime, globals
end

--- Returns ModUtil's `Path` API (Wrap, Override, Restore, Context.Wrap).
function modutilPaths.getPath()
    local runtime = getModUtilRuntime()
    return runtime.Path
end

--- Returns the value currently at a ModUtil path, used to detect a replaced hook target.
function modutilPaths.getTarget(path)
    local _, globals = getModUtilRuntime()
    local node = globals
    if type(path) == "table" then
        for _, key in ipairs(path) do
            if node == nil then return nil end
            node = node[key]
        end
        return node
    end
    for key in string.gmatch(path, "[^%.]+") do
        if node == nil then return nil end
        node = node[key]
    end
    return node
end

return modutilPaths
