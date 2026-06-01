-- luacheck: globals TestControls
-- luacheck: no unused args

local lu = require("luaunit")
local createModuleHostHarness = require("tests/harness/create_module_host_harness")

TestControls = {}

local function createModule(h, opts)
    local module, err = h.public.createModule({
        pluginGuid = opts.pluginGuid,
        config = opts.config or {},
        modpack = "controls-pack",
        id = opts.id,
        name = opts.name,
    })
    lu.assertNil(err)
    module.controls.defineTemplates(opts.templates)
    module.controls.define(opts.controls)
    if opts.drawTab ~= nil then
        module.ui.tab(opts.drawTab)
    else
        module.ui.tab(function() end)
    end
    return module
end

local RangeSelector = {}

function RangeSelector.storage(instance)
    return {
        {
            key = "Mode",
            type = "string",
            default = instance.defaultMode or "Any",
            maxLen = 32,
        },
        {
            key = "Min",
            type = "int",
            default = instance.defaultMin or 1,
            min = instance.min or 0,
            max = instance.max or 10,
        },
    }
end

function RangeSelector.createRuntime(fields)
    local control = {}

    function control:read()
        return {
            mode = fields.Mode:read(),
            min = fields.Min:read(),
        }
    end

    function control:matches(value)
        return fields.Mode:read() == value
    end

    return control
end

function RangeSelector.createUi(fields)
    local control = {}

    function control:read()
        return {
            mode = fields.Mode:read(),
            min = fields.Min:read(),
        }
    end

    function control:field(key)
        return fields[key]
    end

    return control
end

function RangeSelector.draw(draw, control)
    draw.widgets.dropdown(control:field("Mode"), {
        values = { "Any", "Tartarus" },
    })
end

local CommandRange = {}
CommandRange.storage = RangeSelector.storage
CommandRange.createUi = RangeSelector.createUi
CommandRange.createRuntime = RangeSelector.createRuntime
CommandRange.draw = RangeSelector.draw
CommandRange.commands = {
    ResetMode = function(_, _, _, control)
        control:field("Mode"):write("Any")
    end,
}

local SelectionGroup = {}

function SelectionGroup.storage()
    return {
        {
            key = "Rows",
            type = "table",
            minRows = 1,
            maxRows = 3,
            defaultRows = 1,
            row = {
                {
                    key = "Selection",
                    type = "int",
                    default = 0,
                    min = 0,
                    max = 9,
                },
            },
        },
    }
end

function SelectionGroup.createRuntime(fields)
    local control = {}

    function control:count()
        return fields.Rows:count()
    end

    function control:selectedMask(rowIndex)
        return fields.Rows:read(rowIndex, "Selection")
    end

    return control
end

function SelectionGroup.createUi(fields)
    local control = {}

    function control:count()
        return fields.Rows:count()
    end

    function control:setCount(count)
        while fields.Rows:count() < count do
            fields.Rows:append()
        end
        while fields.Rows:count() > count do
            fields.Rows:remove(fields.Rows:count())
        end
    end

    function control:selectionField(rowIndex)
        return fields.Rows:get(rowIndex, "Selection")
    end

    return control
end

SelectionGroup.views = {
    default = function()
        return "default"
    end,
    compact = function(_, _, _, suffix)
        return "compact:" .. tostring(suffix)
    end,
}

local KeyedFlag = {}

function KeyedFlag.storage(instance)
    return {
        {
            key = instance.fieldKey,
            type = "bool",
            default = false,
            hash = false,
        },
    }
end

function KeyedFlag.createUi(fields, instance)
    return {
        set = function(_, value)
            fields[instance.fieldKey]:write(value)
        end,
    }
end

function KeyedFlag.draw() end

function TestControls:setUp()
    self.h = createModuleHostHarness()
    self.h:captureWarnings()
end

function TestControls:tearDown()
    self.h:restoreWarnings()
end

function TestControls:testScalarControlCompilesPrivateStorageAndPhaseRefs()
    local config = {}
    local capturedUiControl = nil
    local capturedRuntimeControl = nil
    local checkRuntimeDuringDraw = false
    local module = createModule(self.h, {
        pluginGuid = "test-controls-scalar",
        config = config,
        id = "ControlsScalar",
        name = "Controls Scalar",
        templates = {
            RangeSelector = RangeSelector,
        },
        controls = {
            PrioritySlot = {
                template = "RangeSelector",
                defaultMode = "Any",
                defaultMin = 2,
            },
        },
        drawTab = function(_, ui)
            capturedUiControl = ui.controls.get("PrioritySlot")
            if checkRuntimeDuringDraw then
                lu.assertEquals(capturedRuntimeControl:read(), {
                    mode = "Any",
                    min = 2,
                })
            end
            lu.assertEquals(capturedUiControl:read(), {
                mode = "Any",
                min = 2,
            })
            capturedUiControl:field("Mode"):write("Tartarus")
            lu.assertErrorMsgContains("storage.private_alias", function()
                ui.data.read("_PrioritySlot:Mode")
            end)
        end,
    })

    lu.assertTrue(module.activate())
    local liveHost = self.h:liveHost("test-controls-scalar")
    local record = self.h.moduleHost.getRecord(liveHost)
    capturedRuntimeControl = record.runtime.controls.get("PrioritySlot")

    lu.assertEquals(capturedRuntimeControl:read(), {
        mode = "Any",
        min = 2,
    })
    checkRuntimeDuringDraw = true
    liveHost.drawTab()
    liveHost.flush()
    lu.assertEquals(config["_PrioritySlot:Mode"], "Tartarus")
    lu.assertEquals(record.runtime.controls.read("PrioritySlot"), {
        mode = "Tartarus",
        min = 2,
    })
    lu.assertEquals(capturedUiControl:read(), {
        mode = "Tartarus",
        min = 2,
    })
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        capturedUiControl:field("Mode"):write("Any")
    end)
end

function TestControls:testGeneratedPrivateAliasesUsePathSeparator()
    local config = {}
    local module = createModule(self.h, {
        pluginGuid = "test-controls-path-aliases",
        config = config,
        id = "ControlsPathAliases",
        name = "Controls Path Aliases",
        templates = {
            KeyedFlag = KeyedFlag,
        },
        controls = {
            A_B = {
                template = "KeyedFlag",
                fieldKey = "C",
            },
            A = {
                template = "KeyedFlag",
                fieldKey = "B_C",
            },
        },
        drawTab = function(_, ui)
            ui.controls.get("A_B"):set(true)
            ui.controls.get("A"):set(true)
        end,
    })

    lu.assertTrue(module.activate())
    self.h:liveHost("test-controls-path-aliases").drawTab()
    self.h:liveHost("test-controls-path-aliases").flush()

    lu.assertEquals(config["_A_B:C"], true)
    lu.assertEquals(config["_A:B_C"], true)
    lu.assertNil(config._A_B_C)
end

function TestControls:testControlsAreCachedPerPhase()
    local uiFirst = nil
    local uiSecond = nil
    local module = createModule(self.h, {
        pluginGuid = "test-controls-cached",
        config = {},
        id = "ControlsCached",
        name = "Controls Cached",
        templates = {
            RangeSelector = RangeSelector,
        },
        controls = {
            PrioritySlot = {
                template = "RangeSelector",
            },
        },
        drawTab = function(_, ui)
            uiFirst = ui.controls.get("PrioritySlot")
            uiSecond = ui.controls.get("PrioritySlot")
        end,
    })

    lu.assertTrue(module.activate())
    local record = self.h.moduleHost.getRecord(self.h:liveHost("test-controls-cached"))
    lu.assertEquals(record.runtime.controls.get("PrioritySlot"), record.runtime.controls.get("PrioritySlot"))
    self.h:liveHost("test-controls-cached").drawTab()
    lu.assertEquals(uiFirst, uiSecond)
end

function TestControls:testDrawControlDispatchesDefaultAndNamedViews()
    local results = {}
    local module = createModule(self.h, {
        pluginGuid = "test-controls-draw-views",
        config = {},
        id = "ControlsDrawViews",
        name = "Controls Draw Views",
        templates = {
            SelectionGroup = SelectionGroup,
        },
        controls = {
            Rewards = {
                template = "SelectionGroup",
            },
        },
        drawTab = function(_, ui)
            local control = ui.controls.get("Rewards")
            results[#results + 1] = ui.draw.control(control)
            results[#results + 1] = ui.draw.control(control, "compact", "arg")
            lu.assertErrorMsgContains("controls.unknown_view", function()
                ui.draw.control(control, "missing")
            end)
        end,
    })

    lu.assertTrue(module.activate())
    self.h:liveHost("test-controls-draw-views").drawTab()
    lu.assertEquals(results, { "default", "compact:arg" })
end

function TestControls:testScopedCommandsLowerIntoPrivateActions()
    local config = {}
    local module = createModule(self.h, {
        pluginGuid = "test-controls-commands",
        config = config,
        id = "ControlsCommands",
        name = "Controls Commands",
        templates = {
            CommandRange = CommandRange,
        },
        controls = {
            PrioritySlot = {
                template = "CommandRange",
                defaultMode = "Tartarus",
            },
        },
        drawTab = function(_, ui)
            local control = ui.controls.get("PrioritySlot")
            control:field("Mode"):write("Tartarus")
            control:command("ResetMode"):stage(true)
            lu.assertErrorMsgContains("actions.private_key", function()
                ui.actions.get("_PrioritySlot:Command:ResetMode")
            end)
        end,
    })

    lu.assertTrue(module.activate())
    local liveHost = self.h:liveHost("test-controls-commands")
    liveHost.drawTab()
    liveHost.flush()

    lu.assertEquals(config["_PrioritySlot:Mode"], "Any")
end

function TestControls:testTableBackedControlUsesSemanticRowMethods()
    local config = {}
    local module = createModule(self.h, {
        pluginGuid = "test-controls-table",
        config = config,
        id = "ControlsTable",
        name = "Controls Table",
        templates = {
            SelectionGroup = SelectionGroup,
        },
        controls = {
            Rewards = {
                template = "SelectionGroup",
            },
        },
        drawTab = function(_, ui)
            local rewards = ui.controls.get("Rewards")
            rewards:setCount(2)
            rewards:selectionField(2):write(5)
        end,
    })

    lu.assertTrue(module.activate())
    local liveHost = self.h:liveHost("test-controls-table")
    local record = self.h.moduleHost.getRecord(liveHost)
    liveHost.drawTab()
    liveHost.flush()

    local rewards = record.runtime.controls.get("Rewards")
    lu.assertEquals(rewards:count(), 2)
    lu.assertEquals(rewards:selectedMask(2), 5)
    lu.assertEquals(config["_Rewards:Rows"][2]["_Rewards:Rows:Selection"], 5)
end

function TestControls:testInvalidDeclarationsFailAtContactPoints()
    local module = self.h.public.createModule({
        pluginGuid = "test-controls-invalid",
        config = {},
        id = "ControlsInvalid",
        name = "Controls Invalid",
    })

    lu.assertErrorMsgContains("controls.invalid_template", function()
        module.controls.defineTemplates({
            Bad = {},
        })
    end)
    lu.assertErrorMsgContains("controls.invalid_template", function()
        module.controls.defineTemplates({
            BadFactory = {
                draw = function() end,
                createUi = true,
            },
        })
    end)
    lu.assertErrorMsgContains("controls.invalid_declaration", function()
        module.controls.define({
            BadControl = {},
        })
    end)
end
