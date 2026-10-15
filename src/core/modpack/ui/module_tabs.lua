-- Module pages: each draws Lib's shared module frame with the pack's staging/snapshot paths for
-- enable, debug, resync and commit.

local ctx = ...

local ui = ctx.rom.ImGui
local createModuleFrame = ctx.createModuleFrame
local moduleRegistry = ctx.moduleRegistry
local staging = ctx.staging
local runtime = ctx.runtime
local snapshotAccess = ctx.snapshotAccess

-- Snapshot of the frame being drawn; frame callbacks only run inside `draw`.
local currentSnapshot = nil
-- One frame per registry entry; a registry refresh builds new entries.
local frames = setmetatable({}, { __mode = "k" })

local function createFrame(entry)
    return createModuleFrame(entry.pluginGuid, {
        enabledTooltip = entry.tooltip,
        isEnabled = function()
            return staging.modules[entry.id] == true
        end,
        setEnabled = function(enabled)
            runtime.toggleEntry(entry, enabled, currentSnapshot)
        end,
        getModule = function()
            return snapshotAccess.getLiveModule(entry, currentSnapshot)
        end,
        commit = function()
            runtime.commitEntryState(entry, currentSnapshot)
        end,
        isDebugMode = function()
            return staging.debug[entry.id] == true
        end,
        setDebugMode = function(enabled)
            if moduleRegistry.snapshot.setDebugEnabled(entry, enabled, currentSnapshot) then
                staging.debug[entry.id] = enabled
            end
        end,
        resync = function()
            runtime.resyncEntry(entry, currentSnapshot)
        end,
    })
end

local function draw(entry, snapshot)
    local frame = frames[entry]
    if frame == nil then
        frame = createFrame(entry)
        frames[entry] = frame
    end
    currentSnapshot = snapshot
    frame.draw(ui)
    currentSnapshot = nil
end

return draw
