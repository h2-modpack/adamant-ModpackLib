-- Lib-owned Hotkeys overview pieces.
-- - `drawAll`: every live Lib module's hotkey requests (conflicts first) and the reserved keys,
--   with the manual reserved-key editor. Drawn as the Hotkeys tab of Lib's settings window.
-- - `drawForOwners`: the same rows filtered to a set of owner ids (a pack's Settings page).
-- - `drawDetectedKey`: a read-only line for the detected Hell2Modding key, only when one was
--   detected.
-- Row edits write the owning module's binding through its staged state and commit (see
-- `row_refs.lua`).

local deps = ...

local hotkeys = deps.hotkeys
local drawWidget = deps.drawWidget
local refForRow = deps.refForRow

local ROW_WIDGET_OPTS = { label = "" }
local PICKER_WIDGET_OPTS = { label = "Reserve", showStatus = false }

local function TextColored(imgui, color, text)
    imgui.TextColored(color[1], color[2], color[3], color[4], text)
end

-- Header text is cached by request identity; a module reload installs new request objects, so
-- stale entries fall out of the weak table.
local rowHeaders = setmetatable({}, { __mode = "k" })

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

-- Detected-key text is cached by detection result identity; a re-detect installs a new table.
local detectedTexts = setmetatable({}, { __mode = "k" })

local function detectedText(detected)
    local text = detectedTexts[detected]
    if text == nil then
        if detected.binding ~= nil then
            text = "Hell2Modding overlay key: " .. detected.binding .. " (reserved)"
        else
            text = "Hell2Modding overlay key: " .. detected.raw .. " (not an F-key; nothing to reserve)"
        end
        detectedTexts[detected] = text
    end
    return text
end

local function drawDetected(ui, detected)
    if detected == nil then
        ui.Text("Hell2Modding overlay key: not detected")
    else
        ui.Text(detectedText(detected))
    end
    ui.SameLine()
    if ui.Button("Detect again##hotkeys-detect") then
        hotkeys.redetectReserved()
    end
end

local function drawManualList(ui, manual)
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

    drawWidget(ui, pickerRef, PICKER_WIDGET_OPTS)
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

-- Separates modules, not rows: consecutive rows of one module share a group. Returns the row's
-- owner for the next call.
local function drawRow(ui, colors, row, previousOwnerId)
    if row.ownerId ~= previousOwnerId then
        ui.Separator()
    end
    TextColored(ui, colors.text, headerForRow(row))
    drawWidget(ui, refForRow(row), ROW_WIDGET_OPTS)
    return row.ownerId
end

---@param ui table ImGui
---@param colors { info: number[], text: number[] } Theme colors.
local function drawAll(ui, colors)
    TextColored(ui, colors.info, "Hotkeys requested by every loaded module. Conflicts are listed first.")
    ui.Spacing()

    local rows = hotkeys.listRows()
    if #rows == 0 then
        ui.Text("No module requests a hotkey.")
    end
    local previousOwnerId = nil
    for _, row in ipairs(rows) do
        previousOwnerId = drawRow(ui, colors, row, previousOwnerId)
    end

    ui.Spacing()
    ui.Separator()
    TextColored(ui, colors.info, "Reserved keys")
    ui.Spacing()
    local reservedKeys = hotkeys.getReserved()
    drawDetected(ui, reservedKeys.detected)
    ui.Spacing()
    drawManualList(ui, reservedKeys.manual)
end

---Rows owned by `ownerIds`, in the overview's order (conflicts first). A conflict with a module
---outside the set names that owner through the row's status line.
---@param ui table ImGui
---@param colors { info: number[], text: number[] } Theme colors.
---@param ownerIds table<string, boolean>
local function drawForOwners(ui, colors, ownerIds)
    local previousOwnerId = nil
    for _, row in ipairs(hotkeys.listRows()) do
        if ownerIds[row.ownerId] then
            previousOwnerId = drawRow(ui, colors, row, previousOwnerId)
        end
    end
    if previousOwnerId == nil then
        ui.Text("No module requests a hotkey.")
    end
end

---@param ui table ImGui
local function drawDetectedKey(ui)
    local detected = hotkeys.getReserved().detected
    if detected ~= nil then
        ui.Text(detectedText(detected))
    end
end

return {
    drawAll = drawAll,
    drawForOwners = drawForOwners,
    drawDetectedKey = drawDetectedKey,
}
