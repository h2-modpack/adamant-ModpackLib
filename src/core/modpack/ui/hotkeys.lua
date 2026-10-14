-- Modpack window "Hotkeys" page: every live Lib module's hotkey requests (conflicts first) and the
-- reserved keys. Edits write the owning module's binding through its staged state and commit
-- (`writeAndFlush`), the same way the window edits module enabled state.

local ctx = ...

local rom = ctx.rom
local ui = rom.ImGui
local colors = ctx.colors
local logging = ctx.logging
local packId = ctx.packId
local hotkeys = ctx.hotkeys
local drawHotkeyWidget = ctx.drawHotkeyWidget
local getLiveModule = ctx.getLiveModule

local ROW_WIDGET_OPTS = { label = "" }
local PICKER_WIDGET_OPTS = { label = "Reserve", showStatus = false }

local function TextColored(imgui, color, text)
    imgui.TextColored(color[1], color[2], color[3], color[4], text)
end

-- Row refs and header text are cached by request identity; a module reload installs new request
-- objects, so stale entries fall out of the weak tables.
local rowRefs = setmetatable({}, { __mode = "k" })
local rowHeaders = setmetatable({}, { __mode = "k" })

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
                logging.warn(packId, "%s hotkey '%s' commit failed: %s", tostring(ownerId), tostring(label), tostring(err))
            end
            return ok
        end,
    }
end

local function refForRow(row)
    local ref = rowRefs[row.request]
    if ref == nil then
        ref = hotkeys.createRef(createRowField(row.ownerId, row.alias, row.label), row.ownerId, row.request)
        rowRefs[row.request] = ref
    end
    return ref
end

local function headerForRow(row)
    local header = rowHeaders[row.request]
    if header == nil or header.moduleName ~= row.moduleName then
        header = {
            moduleName = row.moduleName,
            text = row.moduleName .. " - " .. row.label,
        }
        rowHeaders[row.request] = header
    end
    return header.text
end

local pickerValue = ""
local pickerRef = hotkeys.createRef({
    read = function()
        return pickerValue
    end,
    write = function(_, value)
        pickerValue = value
        return true
    end,
}, nil, nil)

local removeLabels = {}
local function removeLabel(index)
    local label = removeLabels[index]
    if label == nil then
        label = "Remove##hotkeys-reserved-" .. index
        removeLabels[index] = label
    end
    return label
end

local function containsBinding(list, binding)
    for _, entry in ipairs(list) do
        if entry == binding then
            return true
        end
    end
    return false
end

local function drawDetected(detected)
    if detected == nil then
        ui.Text("Hell2Modding overlay key: not detected")
    elseif detected.binding ~= nil then
        ui.Text("Hell2Modding overlay key: " .. detected.binding .. " (reserved)")
    else
        ui.Text("Hell2Modding overlay key: " .. detected.raw .. " (not an F-key; nothing to reserve)")
    end
    ui.SameLine()
    if ui.Button("Detect again##hotkeys-detect") then
        hotkeys.redetectReserved()
    end
end

local function drawManualList(manual)
    ui.Text("Reserved for other tools:")
    if #manual == 0 then
        ui.Text("  (none)")
    end
    for index, entry in ipairs(manual) do
        ui.Text("  " .. entry)
        ui.SameLine()
        if ui.Button(removeLabel(index)) then
            local nextList = {}
            for otherIndex, other in ipairs(manual) do
                if otherIndex ~= index then
                    nextList[#nextList + 1] = other
                end
            end
            hotkeys.setManualReserved(nextList)
            return
        end
    end

    drawHotkeyWidget(ui, pickerRef, PICKER_WIDGET_OPTS)
    ui.SameLine()
    if ui.Button("Add##hotkeys-reserved-add") and pickerValue ~= "" then
        if not containsBinding(manual, pickerValue) then
            local nextList = {}
            for _, other in ipairs(manual) do
                nextList[#nextList + 1] = other
            end
            nextList[#nextList + 1] = pickerValue
            hotkeys.setManualReserved(nextList)
        end
        pickerValue = ""
    end
end

local function draw()
    TextColored(ui, colors.info, "Hotkeys requested by every loaded module. Conflicts are listed first.")
    ui.Spacing()

    local rows = hotkeys.listRows()
    if #rows == 0 then
        ui.Text("No module requests a hotkey.")
    end
    for _, row in ipairs(rows) do
        ui.Separator()
        TextColored(ui, colors.text, headerForRow(row))
        drawHotkeyWidget(ui, refForRow(row), ROW_WIDGET_OPTS)
    end

    ui.Spacing()
    ui.Separator()
    TextColored(ui, colors.info, "Reserved keys")
    ui.Spacing()
    local reservedKeys = hotkeys.getReserved()
    drawDetected(reservedKeys.detected)
    ui.Spacing()
    drawManualList(reservedKeys.manual)
end

return draw
