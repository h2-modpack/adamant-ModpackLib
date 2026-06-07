-- luacheck: globals TestControls
-- luacheck: no unused args

local lu = require("luaunit")
local createManagedModuleHarness = require("tests/harness/create_managed_module_harness")

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

    function control:readUnknownRowAlias()
        return fields.Rows:read(1, "Enabled")
    end

    function control:readInternalRowAlias()
        return fields.Rows:read(1, "_Rewards:Rows:Selection")
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

local PackedFlags = {}

function PackedFlags.storage()
    return {
        {
            key = "Value",
            type = "packedInt",
            default = 0,
            width = 2,
            bits = {
                { key = "Alpha", type = "bool", offset = 0, width = 1, default = false },
                { key = "Beta", type = "bool", offset = 1, width = 1, default = false },
            },
        },
    }
end

function PackedFlags.createUi(fields)
    return {
        field = function()
            return fields.Value
        end,
    }
end

function PackedFlags.draw() end

local FilteredValue = {}

function FilteredValue.storage()
    return {
        {
            key = "Value",
            type = "int",
            default = 1,
            min = 0,
            max = 10,
        },
        {
            key = "Filter",
            type = "string",
            persist = false,
            hash = false,
            default = "",
            maxLen = 64,
        },
    }
end

function FilteredValue.createRuntime(fields)
    return {
        read = function()
            return fields.Value:read()
        end,
        hasFilter = function()
            return fields.Filter ~= nil
        end,
    }
end

function FilteredValue.createUi(fields)
    return {
        read = function()
            return fields.Value:read()
        end,
        hasFilter = function()
            return fields.Filter ~= nil
        end,
        writeFilter = function(_, value)
            return fields.Filter:write(value)
        end,
        readFilter = function()
            return fields.Filter:read()
        end,
    }
end

function FilteredValue.draw() end

function TestControls:setUp()
    self.h = createManagedModuleHarness()
    self.h:captureWarnings()
end

function TestControls:tearDown()
    self.h:restoreWarnings()
end

function TestControls:testScalarControlCompilesPrivateStorageAndCallbackRefs()
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
            lu.assertErrorMsgContains("controls.unknown_field_alias", function()
                capturedUiControl:field("Mode"):readAlias("Enabled")
            end)
            lu.assertErrorMsgContains("storage.private_alias", function()
                ui.data.read("_PrioritySlot:Mode")
            end)
        end,
    })

    lu.assertTrue(module.activate())
    local liveModule = self.h:liveModule("test-controls-scalar")
    local record = self.h.managedModule.getRecord(liveModule)
    capturedRuntimeControl = record.runtime.controls.get("PrioritySlot")

    lu.assertEquals(capturedRuntimeControl:read(), {
        mode = "Any",
        min = 2,
    })
    checkRuntimeDuringDraw = true
    liveModule.drawTab()
    liveModule.flush()
    lu.assertEquals(config["_PrioritySlot:Mode"], "Tartarus")
    lu.assertEquals(record.runtime.controls.read("PrioritySlot"), {
        mode = "Tartarus",
        min = 2,
    })
    lu.assertEquals(capturedUiControl:read(), {
        mode = "Tartarus",
        min = 2,
    })
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
    self.h:liveModule("test-controls-path-aliases").drawTab()
    self.h:liveModule("test-controls-path-aliases").flush()

    lu.assertEquals(config["_A_B:C"], true)
    lu.assertEquals(config["_A:B_C"], true)
    lu.assertNil(config._A_B_C)
end

function TestControls:testControlsAreCachedPerSurface()
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
    local record = self.h.managedModule.getRecord(self.h:liveModule("test-controls-cached"))
    lu.assertEquals(record.runtime.controls.get("PrioritySlot"), record.runtime.controls.get("PrioritySlot"))
    self.h:liveModule("test-controls-cached").drawTab()
    lu.assertEquals(uiFirst, uiSecond)
end

function TestControls:testRuntimeControlsSkipUiOnlyFields()
    local config = {}
    local capturedUiControl = nil
    local module = createModule(self.h, {
        pluginGuid = "test-controls-ui-only-field",
        config = config,
        id = "ControlsUiOnlyField",
        name = "Controls UI Only Field",
        templates = {
            FilteredValue = FilteredValue,
        },
        controls = {
            Searchable = {
                template = "FilteredValue",
            },
        },
        drawTab = function(_, ui)
            capturedUiControl = ui.controls.get("Searchable")
            lu.assertTrue(capturedUiControl:hasFilter())
            capturedUiControl:writeFilter("Zeus")
            lu.assertEquals(capturedUiControl:readFilter(), "Zeus")
        end,
    })

    lu.assertTrue(module.activate())
    local liveModule = self.h:liveModule("test-controls-ui-only-field")
    local record = self.h.managedModule.getRecord(liveModule)
    local runtimeControl = record.runtime.controls.get("Searchable")
    lu.assertEquals(runtimeControl:read(), 1)
    lu.assertErrorMsgContains("controls.unavailable_field", function()
        runtimeControl:hasFilter()
    end)

    liveModule.drawTab()
    liveModule.flush()

    lu.assertEquals(capturedUiControl:read(), 1)
    lu.assertEquals(config["_Searchable:Value"], 1)
    lu.assertNil(config["_Searchable:Filter"])
end

function TestControls:testControlsRejectStatusStorage()
    local module = createModule(self.h, {
        pluginGuid = "test-controls-status-field",
        config = {},
        id = "ControlsStatusField",
        name = "Controls Status Field",
        templates = {
            StatusValue = {
                storage = function()
                    return {
                        {
                            key = "Marker",
                            type = "bool",
                            mode = "runtime",
                            persist = false,
                            hash = false,
                            default = false,
                        },
                    }
                end,
                draw = function() end,
            },
        },
        controls = {
            Recording = {
                template = "StatusValue",
            },
        },
    })

    local ok, err = module.activate()
    lu.assertFalse(ok)
    lu.assertStrContains(err, "controls cannot declare status storage")
end

function TestControls:testControlSchemasExposeSemanticAliasesOnly()
    local module = createModule(self.h, {
        pluginGuid = "test-controls-semantic-schema",
        config = {},
        id = "ControlsSemanticSchema",
        name = "Controls Semantic Schema",
        templates = {
            PackedFlags = PackedFlags,
        },
        controls = {
            Flags = {
                template = "PackedFlags",
            },
        },
        drawTab = function(_, ui)
            local field = ui.controls.get("Flags"):field()
            local schema = field:schema()
            lu.assertEquals(schema.alias, "Value")
            lu.assertEquals(schema.bits[1].alias, "Alpha")
            lu.assertEquals(schema.bits[2].alias, "Beta")
            field:writeAlias("Alpha", true)
            lu.assertTrue(field:readAlias("Alpha"))
            lu.assertErrorMsgContains("controls.unknown_field_alias", function()
                field:readAlias("_Flags:Value:Alpha")
            end)
        end,
    })

    lu.assertTrue(module.activate())
    self.h:liveModule("test-controls-semantic-schema").drawTab()
end

function TestControls:testNestedControlPackedSchemaAliasesStaySemanticForWidgets()
    local module = createModule(self.h, {
        pluginGuid = "test-controls-nested-semantic-schema",
        config = {},
        id = "ControlsNestedSemanticSchema",
        name = "Controls Nested Semantic Schema",
        templates = {
            Rows = {
                storage = {
                    {
                        key = "Rows",
                        type = "table",
                        defaultRows = 1,
                        row = {
                            {
                                key = "Packed",
                                type = "packedInt",
                                width = 2,
                                default = 0,
                                bits = {
                                    { key = "Alpha", offset = 0, width = 1, type = "bool", default = false },
                                    { key = "Beta", offset = 1, width = 1, type = "bool", default = false },
                                },
                            },
                        },
                    },
                },
                createUi = function(fields)
                    return {
                        packedField = function()
                            return fields.Rows:get(1, "Packed")
                        end,
                    }
                end,
                draw = function() end,
            },
        },
        controls = {
            Rows = {
                template = "Rows",
            },
        },
        drawTab = function(_, ui)
            local field = ui.controls.get("Rows"):packedField()
            local children = self.h.harness.storage.packed.getPackedAliases(field:schema())
            lu.assertEquals(children[1].alias, "Alpha")
            lu.assertEquals(children[2].alias, "Beta")
            field:writeAlias("Alpha", true)
            lu.assertTrue(field:readAlias(children[1].alias))
        end,
    })

    lu.assertTrue(module.activate())
    self.h:liveModule("test-controls-nested-semantic-schema").drawTab()
end

function TestControls:testDrawControlDispatchesDefaultAndNamedViews()
    local results = {}
    local runtimeControl = nil
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
            lu.assertErrorMsgContains("controls.invalid_render_target", function()
                ui.draw.control(runtimeControl)
            end)
        end,
    })

    lu.assertTrue(module.activate())
    local liveModule = self.h:liveModule("test-controls-draw-views")
    local record = self.h.managedModule.getRecord(liveModule)
    runtimeControl = record.runtime.controls.get("Rewards")
    liveModule.drawTab()
    lu.assertEquals(results, { "default", "compact:arg" })
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
            lu.assertErrorMsgContains("controls.unknown_field_alias", function()
                rewards:readUnknownRowAlias()
            end)
            lu.assertErrorMsgContains("controls.unknown_field_alias", function()
                rewards:readInternalRowAlias()
            end)
        end,
    })

    lu.assertTrue(module.activate())
    local liveModule = self.h:liveModule("test-controls-table")
    local record = self.h.managedModule.getRecord(liveModule)
    liveModule.drawTab()
    liveModule.flush()

    local rewards = record.runtime.controls.get("Rewards")
    lu.assertEquals(rewards:count(), 2)
    lu.assertEquals(rewards:selectedMask(2), 5)
    lu.assertEquals(config["_Rewards:Rows"][2]["_Rewards:Rows:Selection"], 5)
end

function TestControls:testUiControlsResetNamedAndAllBoundStorage()
    local config = {}
    local resetNamedResult = nil
    local resetModuleResult = nil
    local module = createModule(self.h, {
        pluginGuid = "test-controls-reset",
        config = config,
        id = "ControlsReset",
        name = "Controls Reset",
        templates = {
            RangeSelector = RangeSelector,
            SelectionGroup = SelectionGroup,
        },
        controls = {
            PrioritySlot = {
                template = "RangeSelector",
                defaultMin = 2,
            },
            Rewards = {
                template = "SelectionGroup",
            },
        },
        drawTab = function(_, ui)
            local priority = ui.controls.get("PrioritySlot")
            priority:field("Mode"):write("Tartarus")
            priority:field("Min"):write(5)

            local rewards = ui.controls.get("Rewards")
            rewards:setCount(2)
            rewards:selectionField(2):write(5)

            resetNamedResult = { ui.controls.reset("PrioritySlot") }
            lu.assertEquals(priority:read(), {
                mode = "Any",
                min = 2,
            })
            lu.assertEquals(rewards:count(), 2)

            resetModuleResult = { ui.resetAll() }
            lu.assertEquals(rewards:count(), 1)
            lu.assertEquals(rewards:selectionField(1):read(), 0)
        end,
    })

    lu.assertTrue(module.activate())
    local liveModule = self.h:liveModule("test-controls-reset")
    local record = self.h.managedModule.getRecord(liveModule)
    liveModule.drawTab()
    liveModule.flush()

    lu.assertEquals(resetNamedResult, { true, 2 })
    lu.assertEquals(resetModuleResult, { true, 1 })
    lu.assertEquals(record.runtime.controls.read("PrioritySlot"), {
        mode = "Any",
        min = 2,
    })
    local rewards = record.runtime.controls.get("Rewards")
    lu.assertEquals(rewards:count(), 1)
    lu.assertEquals(rewards:selectedMask(1), 0)
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

    local badPrepareModule, err = self.h.public.createModule({
        pluginGuid = "test-controls-bad-prepare",
        config = {},
        id = "ControlsBadPrepare",
        name = "Controls Bad Prepare",
    })
    lu.assertNil(err)
    badPrepareModule.controls.defineTemplates({
        BadPrepare = {
            prepare = function()
                return true
            end,
            draw = function() end,
        },
    })
    badPrepareModule.controls.define({
        BadControl = {
            template = "BadPrepare",
        },
    })
    badPrepareModule.ui.tab(function() end)

    local ok, activateErr = badPrepareModule.activate()
    lu.assertFalse(ok)
    lu.assertStrContains(activateErr, "controls.invalid_declaration")
    lu.assertStrContains(activateErr, "prepare must return a table")
end
