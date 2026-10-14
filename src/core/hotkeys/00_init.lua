-- Hotkey registry, ownership resolution, and the shared always-draw dispatch tick.
--
-- Modules request hotkeys at declaration; activation installs each module's requests through a
-- receipt. Lib owns the binding storage, decides which request owns each key, and dispatches presses
-- to active owners only.

local deps = ...

local logging = deps.logging
local receipt = deps.receipt
local rom = deps.rom
local libConfig = deps.libConfig
local bindings = deps.bindings
local anchor = deps.hotkeyRegistry

local resolution = import('core/hotkeys/resolution.lua', nil, {
    bindings = bindings,
})
local reserved = import('core/hotkeys/reserved.lua', nil, {
    rom = rom,
    bindings = bindings,
})

-- Hot-reload-stable hotkey anchors:
-- - `installs`: ownerId -> committed install. Activation receipts from any Lib import write here
--   and the current import's tick reads it.
-- - `owners`: binding -> request key of the current owner (ownership history; in memory only).
-- - `packOrders`: packId -> { index, guids } pushed by the modpack layer for the tie-break.
-- - `revision`: bumped by install commit/rollback/retire and pack order changes.
-- - `tickRegistered` / `dispatch`: the always-draw callback is registered once per process and
--   late-reads `dispatch`, which every import overwrites.
anchor.installs = anchor.installs or {}
anchor.owners = anchor.owners or {}
anchor.packOrders = anchor.packOrders or {}
anchor.revision = anchor.revision or 0

local installs = anchor.installs

local hotkeys = {}

local REF_KIND = "AdamantHotkeyRef"
local REQUEST_KEY_SEPARATOR = "\n"
local MODIFIER_KEY_NAMES = {
    ctrl = { "LeftCtrl", "RightCtrl" },
    shift = { "LeftShift", "RightShift" },
    alt = { "LeftAlt", "RightAlt" },
}

local function bumpRevision()
    anchor.revision = anchor.revision + 1
end

-- Rebuildable view over the anchors. Rebuilt when the revision, reserved sources, or a committed
-- binding/enabled value changes; per-frame refresh only compares cached values.
local view = {
    revision = nil,
    detectedRead = false,
    detected = nil,
    manualSource = nil,
    manualList = {},
    reservedMap = {},
    entries = {},
    byOwner = {},
    rows = {},
    dispatchList = {},
    modifierCodes = nil,
}

local function resolveKeyCode(name)
    local keys = rom.ImGuiKey
    if type(keys) ~= "table" then
        return nil
    end
    return keys[name] or keys["ImGuiKey_" .. name]
end

local function resolveModifierCodes()
    local codes = {}
    for modifier, names in pairs(MODIFIER_KEY_NAMES) do
        local list = {}
        for _, name in ipairs(names) do
            local code = resolveKeyCode(name)
            if code ~= nil then
                list[#list + 1] = code
            end
        end
        codes[modifier] = list
    end
    return codes
end

local function buildPackRanks()
    local ranks = {}
    for _, order in pairs(anchor.packOrders) do
        for position, guid in ipairs(order.guids) do
            local existing = ranks[guid]
            if existing == nil or order.index < existing.index
                or (order.index == existing.index and position < existing.position) then
                ranks[guid] = { index = order.index, position = position }
            end
        end
    end
    return ranks
end

-- Tie-break: pack module order (modules outside a pack after pack modules), then plugin GUID,
-- then request declaration order.
local function rebuildEntries()
    local ranks = buildPackRanks()
    local entries = {}
    for ownerId, install in pairs(installs) do
        for _, request in ipairs(install.requests) do
            entries[#entries + 1] = {
                ownerId = ownerId,
                install = install,
                request = request,
                key = ownerId .. REQUEST_KEY_SEPARATOR .. request.id,
                rank = ranks[ownerId],
                binding = nil,
                enabled = nil,
                status = nil,
            }
        end
    end
    table.sort(entries, function(left, right)
        local leftRank, rightRank = left.rank, right.rank
        if leftRank ~= nil and rightRank == nil then
            return true
        elseif leftRank == nil and rightRank ~= nil then
            return false
        elseif leftRank ~= nil and rightRank ~= nil and leftRank ~= rightRank then
            if leftRank.index ~= rightRank.index then
                return leftRank.index < rightRank.index
            end
            if leftRank.position ~= rightRank.position then
                return leftRank.position < rightRank.position
            end
        end
        if left.ownerId ~= right.ownerId then
            return left.ownerId < right.ownerId
        end
        return left.request.order < right.request.order
    end)

    local byOwner = {}
    for _, entry in ipairs(entries) do
        byOwner[entry.ownerId] = byOwner[entry.ownerId] or {}
        byOwner[entry.ownerId][entry.request.id] = entry
    end
    view.entries = entries
    view.byOwner = byOwner
end

local function moduleNameOf(install)
    local meta = install.host.getMeta()
    return tostring(meta and meta.name or install.host.getModuleId() or install.ownerId)
end

local function describeStatus(status)
    local state = status.state
    local binding = status.binding
    if state == "active" then
        return binding .. " - active"
    elseif state == "conflict" then
        return string.format("%s is used by %s (%s); this binding is inactive",
            binding, status.owner.moduleName, status.owner.label)
    elseif state == "reserved" then
        return string.format("%s is reserved (%s)", binding, status.reason)
    elseif state == "invalid" then
        return string.format("'%s' is not a valid hotkey", binding)
    elseif state == "disabled" then
        return binding .. " - inactive while the module is disabled"
    end
    return "Not bound"
end

-- Status tables are replaced only when their signature changes, so callers can cache by identity
-- and the status text is built once per change.
local function statusFor(entry, result, ownerEntry)
    local previous = entry.status
    local ownerName = ownerEntry and moduleNameOf(ownerEntry.install) or nil
    local ownerLabel = ownerEntry and ownerEntry.request.label or nil
    if previous ~= nil
        and previous.state == result.state
        and previous.binding == entry.binding
        and previous.reason == result.reservedBy
        and (previous.owner and previous.owner.moduleName) == ownerName
        and (previous.owner and previous.owner.label) == ownerLabel then
        return previous
    end
    local status = {
        state = result.state,
        binding = entry.binding,
        owner = ownerEntry and { moduleName = ownerName, label = ownerLabel } or nil,
        reason = result.reservedBy,
    }
    status.text = describeStatus(status)
    return status
end

local function buildDispatch(entry)
    local parsed = bindings.parse(entry.binding)
    local keyCode = parsed and resolveKeyCode(parsed.key) or nil
    if keyCode == nil then
        return nil
    end
    return {
        keyCode = keyCode,
        ctrl = parsed.ctrl,
        shift = parsed.shift,
        alt = parsed.alt,
        entry = entry,
    }
end

local function resolveView()
    local entries = view.entries
    local inputs = {}
    for index, entry in ipairs(entries) do
        inputs[index] = {
            key = entry.key,
            binding = entry.binding,
            enabled = entry.enabled,
        }
    end
    local results = resolution.resolve(inputs, anchor.owners, view.reservedMap)

    local dispatchList = {}
    local conflictRows = {}
    local otherRows = {}
    for index, entry in ipairs(entries) do
        local result = results[index]
        local ownerEntry = result.ownerIndex and entries[result.ownerIndex] or nil
        entry.status = statusFor(entry, result, ownerEntry)
        if result.state == "active" then
            dispatchList[#dispatchList + 1] = buildDispatch(entry)
        end
        local row = {
            ownerId = entry.ownerId,
            id = entry.request.id,
            label = entry.request.label,
            tooltip = entry.request.tooltip,
            alias = entry.request.alias,
            request = entry.request,
            moduleName = moduleNameOf(entry.install),
            status = entry.status,
        }
        if result.state == "conflict" then
            conflictRows[#conflictRows + 1] = row
        else
            otherRows[#otherRows + 1] = row
        end
    end
    for _, row in ipairs(otherRows) do
        conflictRows[#conflictRows + 1] = row
    end

    view.dispatchList = dispatchList
    view.rows = conflictRows
    view.modifierCodes = resolveModifierCodes()
end

-- Change signal: the anchor revision (install commit/rollback/retire, pack order), the reserved
-- sources, and a per-request compare of the committed binding and enabled state. The compare is a
-- few table reads per request and allocates nothing; resolution runs only when something changed.
local function refresh()
    local dirty = false
    if view.revision ~= anchor.revision then
        rebuildEntries()
        view.revision = anchor.revision
        dirty = true
    end
    local reservedDirty = false
    if not view.detectedRead then
        view.detected = reserved.detectHell2Modding()
        view.detectedRead = true
        reservedDirty = true
    end
    local manualSource = libConfig.ReservedHotkeys
    if manualSource ~= view.manualSource then
        view.manualSource = manualSource
        view.manualList = reserved.parseManualList(manualSource)
        reservedDirty = true
    end
    if reservedDirty then
        view.reservedMap = reserved.buildMap(view.detected, view.manualList)
        dirty = true
    end
    for _, entry in ipairs(view.entries) do
        local install = entry.install
        local binding = install.readCommitted(entry.request.alias)
        local enabled = install.host.isEnabled() == true
        if binding ~= entry.binding or enabled ~= entry.enabled then
            entry.binding = binding
            entry.enabled = enabled
            dirty = true
        end
    end
    if dirty then
        resolveView()
    end
end

local function anyDown(imgui, codes)
    for index = 1, #codes do
        if imgui.IsKeyDown(codes[index]) == true then
            return true
        end
    end
    return false
end

local function press(entry)
    local install = entry.install
    local request = entry.request
    local ok, err = pcall(request.onPress, install.host, install.runtime)
    if not ok and install.reported[request.id] ~= entry.binding then
        install.reported[request.id] = entry.binding
        logging.violate("hotkeys.on_press_failed", "%s hotkey '%s' (%s) onPress failed: %s",
            moduleNameOf(install), request.label, tostring(entry.binding), tostring(err))
    end
end

local function dispatchFrame()
    refresh()
    local list = view.dispatchList
    if #list == 0 or rom.gui.is_open() == true then
        return
    end
    local imgui = rom.ImGui
    local codes = view.modifierCodes
    local modifiersRead = false
    local ctrl, shift, alt = false, false, false
    for index = 1, #list do
        local dispatch = list[index]
        if imgui.IsKeyPressed(dispatch.keyCode, false) == true then
            if not modifiersRead then
                ctrl = anyDown(imgui, codes.ctrl)
                shift = anyDown(imgui, codes.shift)
                alt = anyDown(imgui, codes.alt)
                modifiersRead = true
            end
            if dispatch.ctrl == ctrl and dispatch.shift == shift and dispatch.alt == alt then
                press(dispatch.entry)
            end
        end
    end
end

local dispatchFailed = false
anchor.dispatch = function()
    if dispatchFailed then
        return
    end
    local ok, err = pcall(dispatchFrame)
    if not ok then
        dispatchFailed = true
        logging.violate("hotkeys.dispatch_failed", "hotkey tick disabled until Lib reloads: %s", tostring(err))
    end
end

if not anchor.tickRegistered and type(rom.gui) == "table" and type(rom.gui.add_always_draw_imgui) == "function" then
    rom.gui.add_always_draw_imgui(function()
        local dispatch = anchor.dispatch
        if dispatch ~= nil then
            dispatch()
        end
    end)
    anchor.tickRegistered = true
end

---Installs one module's requests. Commit publishes them, rollback restores the previous
---generation's install, retire removes only this install.
---@param ownerId string
---@param inputs AdamantModpackLib.HotkeyCapabilityInputs
---@return AdamantModpackLib.Receipt?
function hotkeys.install(ownerId, inputs)
    if #inputs.requests == 0 then
        return nil
    end
    local install = {
        ownerId = ownerId,
        requests = inputs.requests,
        host = inputs.host,
        runtime = inputs.runtime,
        readCommitted = inputs.readCommitted,
        reported = {},
    }
    local previous = nil
    return receipt.create({
        name = "hotkeys",
        phase = receipt.PHASE_EFFECTS,
        commit = function()
            previous = installs[ownerId]
            installs[ownerId] = install
            bumpRevision()
            return true, nil
        end,
        rollback = function()
            if installs[ownerId] == install then
                installs[ownerId] = previous
                bumpRevision()
            end
            return true, nil
        end,
        retire = function()
            if installs[ownerId] == install then
                installs[ownerId] = nil
                bumpRevision()
            end
            return true, nil
        end,
    })
end

---Current status of one installed request, or nil when the owner has no committed install.
---@param ownerId string
---@param id string
---@return AdamantModpackLib.HotkeyStatus?
function hotkeys.status(ownerId, id)
    refresh()
    local owned = view.byOwner[ownerId]
    local entry = owned and owned[id] or nil
    return entry and entry.status or nil
end

---Every installed request across live modules, conflicts first, then tie-break order.
---@return AdamantModpackLib.HotkeyRow[]
function hotkeys.listRows()
    refresh()
    return view.rows
end

---Pushed by the modpack layer after it orders a pack's modules. A new or changed order is
---load-time ordering, so recorded ownership is dropped and the tie-break decides again.
---@param packId string
---@param packIndex integer
---@param pluginGuids string[]
function hotkeys.setPackOrder(packId, packIndex, pluginGuids)
    local previous = anchor.packOrders[packId]
    if previous ~= nil and previous.index == packIndex and #previous.guids == #pluginGuids then
        local same = true
        for index, guid in ipairs(pluginGuids) do
            if previous.guids[index] ~= guid then
                same = false
                break
            end
        end
        if same then
            return
        end
    end
    local guids = {}
    for index, guid in ipairs(pluginGuids) do
        guids[index] = guid
    end
    anchor.packOrders[packId] = {
        index = packIndex,
        guids = guids,
    }
    for binding in pairs(anchor.owners) do
        anchor.owners[binding] = nil
    end
    bumpRevision()
end

---@return { detected: AdamantModpackLib.HotkeyDetectedReserve?, manual: string[] }
function hotkeys.getReserved()
    refresh()
    return {
        detected = view.detected,
        manual = view.manualList,
    }
end

---Replaces the manual reserved list in Lib config; the next refresh picks it up.
---@param list string[]
function hotkeys.setManualReserved(list)
    libConfig.ReservedHotkeys = reserved.formatManualList(list)
end

---Reads the Hell2Modding hotkey config again on the next refresh.
function hotkeys.redetectReserved()
    view.detectedRead = false
end

---@param field { read: fun(self): any, write: fun(self, value: any): any }
---@param ownerId string? Owner whose status the widget shows; nil for a status-less picker.
---@param request AdamantModpackLib.HotkeyRequest?
---@return AdamantModpackLib.HotkeyRef
function hotkeys.createRef(field, ownerId, request)
    local suffix = tostring(ownerId or "picker") .. "-" .. tostring(request and request.id or tostring(field))
    return {
        _kind = REF_KIND,
        field = field,
        ownerId = ownerId,
        id = request and request.id or nil,
        label = request and request.label or "",
        tooltip = request and request.tooltip or nil,
        modifierComboId = "##hotkey-modifier-" .. suffix,
        keyComboId = "##hotkey-key-" .. suffix,
        pendingPrefix = nil,
    }
end

function hotkeys.isRef(value)
    return type(value) == "table" and rawget(value, "_kind") == REF_KIND
end

---@param ref AdamantModpackLib.HotkeyRef
---@return AdamantModpackLib.HotkeyStatus?
function hotkeys.refStatus(ref)
    if ref.ownerId == nil then
        return nil
    end
    return hotkeys.status(ref.ownerId, ref.id)
end

---Builds a module's `runtime.hotkeys` and `ui.hotkeys` surfaces over its compiled requests.
---@param ownerId string
---@param requests AdamantModpackLib.HotkeyRequest[]
---@param staged AdamantModpackLib.StagedState
---@return table runtimeSurface
---@return table uiSurface
function hotkeys.createSurfaces(ownerId, requests, staged)
    local byId = {}
    for _, request in ipairs(requests) do
        byId[request.id] = request
    end
    local function requireRequest(context, id)
        local request = byId[id]
        if request == nil then
            logging.violate("hotkeys.unknown_request", "%s: unknown hotkey '%s'", context, tostring(id))
        end
        return request
    end

    local runtimeSurface = {
        status = function(id)
            requireRequest("runtime.hotkeys.status", id)
            return hotkeys.status(ownerId, id)
        end,
    }

    local refs = {}
    local uiSurface = {
        get = function(id)
            local request = requireRequest("ui.hotkeys.get", id)
            local ref = refs[id]
            if ref == nil then
                ref = hotkeys.createRef(staged.get(request.alias), ownerId, request)
                refs[id] = ref
            end
            return ref
        end,
        status = function(id)
            requireRequest("ui.hotkeys.status", id)
            return hotkeys.status(ownerId, id)
        end,
    }
    return runtimeSurface, uiSurface
end

return hotkeys
