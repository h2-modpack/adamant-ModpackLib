local lu = require('luaunit')

TestSpecialState = {}

function TestSpecialState:setUp()
    CaptureWarnings()
end

function TestSpecialState:tearDown()
    RestoreWarnings()
end

function TestSpecialState:testStagingMirrorsConfig()
    local config = { Mode = "Fast", Strict = true }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
        { type = "checkbox", configKey = "Strict" },
    }

    local staging = lib.createSpecialState(config, schema)

    lu.assertEquals(staging.Mode, "Fast")
    lu.assertEquals(staging.Strict, true)
end

function TestSpecialState:testSnapshotReReadsConfig()
    local config = { Mode = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local staging, snapshot = lib.createSpecialState(config, schema)
    lu.assertEquals(staging.Mode, "Fast")

    config.Mode = "Slow"
    snapshot()
    lu.assertEquals(staging.Mode, "Slow")
end

function TestSpecialState:testSyncFlushesToConfig()
    local config = { Mode = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local staging, _, sync = lib.createSpecialState(config, schema)
    staging.Mode = "Slow"

    lu.assertEquals(config.Mode, "Fast") -- not yet synced
    sync()
    lu.assertEquals(config.Mode, "Slow")
end

function TestSpecialState:testNestedConfigKey()
    local config = { Parent = { Child = "value" } }
    local schema = {
        { type = "dropdown", configKey = {"Parent", "Child"}, values = { "value", "other" }, default = "value" },
    }

    local staging, snapshot, sync = lib.createSpecialState(config, schema)
    lu.assertEquals(staging.Parent.Child, "value")

    staging.Parent.Child = "other"
    sync()
    lu.assertEquals(config.Parent.Child, "other")

    config.Parent.Child = "value"
    snapshot()
    lu.assertEquals(staging.Parent.Child, "value")
end
