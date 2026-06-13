-- luacheck: globals TestShellSmoke

local lu = require("luaunit")
local shellSmoke = require("tests/harness/shell_smoke")

TestShellSmoke = {}

local function writeFile(path, contents)
    local file = assert(io.open(path, "w"))
    file:write(contents)
    file:close()
end

local function makeDir(path)
    local ok = os.execute('mkdir -p "' .. path .. '"')
    if ok ~= true and ok ~= 0 then
        error("failed to create directory: " .. tostring(path), 2)
    end
end

local function makeTempDir()
    local path = os.tmpname()
    os.remove(path)
    makeDir(path)
    return path
end

local function writePackage(root, repoPath, namespace, name)
    makeDir(root .. "/" .. repoPath)
    writeFile(root .. "/" .. repoPath .. "/thunderstore.toml", string.format([[
[package]
namespace = "%s"
name = "%s"
versionNumber = "1.0.0"
]], namespace, name))
end

local function writeCoordinator(root)
    writePackage(root, "team-Pack_Modpack", "team", "Pack_Modpack")
    makeDir(root .. "/team-Pack_Modpack/src")
    writeFile(root .. "/team-Pack_Modpack/src/main.lua", [[
local PACK_ID = "test-pack"
]])
end

local function writeModule(root, name)
    writePackage(root, "Submodules/team-" .. name, "team", name)
    makeDir(root .. "/Submodules/team-" .. name .. "/src")
end

local function writeGitmodules(root, paths)
    local lines = {}
    for _, path in ipairs(paths) do
        lines[#lines + 1] = string.format([[
[submodule "%s"]
    path = %s
    url = https://example.invalid/%s.git
]], path, path, path:gsub("^.*/", ""))
    end
    writeFile(root .. "/.gitmodules", table.concat(lines))
end

function TestShellSmoke.testBuildManifestDerivesRegisteredShellLayout()
    local root = makeTempDir()
    writeCoordinator(root)
    writeModule(root, "Second")
    writeModule(root, "First")
    writeGitmodules(root, {
        "team-Pack_Modpack",
        "Submodules/team-Second",
        "Submodules/team-First",
    })

    local manifest = shellSmoke.buildManifest({
        rootDir = root,
        libDir = "Lib",
    })

    lu.assertEquals(manifest.libSrcDir, root .. "/Lib/src")
    lu.assertEquals(manifest.packId, "test-pack")
    lu.assertEquals(manifest.coordinator.pluginGuid, "team-Pack_Modpack")
    lu.assertEquals(manifest.coordinator.srcDir, root .. "/team-Pack_Modpack/src")
    lu.assertEquals(#manifest.modules, 2)
    lu.assertEquals(manifest.modules[1].pluginGuid, "team-First")
    lu.assertEquals(manifest.modules[1].moduleSrcDir, root .. "/Submodules/team-First/src")
    lu.assertEquals(manifest.modules[1].fixturePath, root .. "/Submodules/team-First/tests/smoke_env.lua")
    lu.assertEquals(manifest.modules[1].expectedPackId, "test-pack")
    lu.assertEquals(manifest.modules[1].expectedModuleId, "First")
end

function TestShellSmoke.testBuildManifestAllowsEmptyShell()
    local root = makeTempDir()
    writeCoordinator(root)
    writeGitmodules(root, {
        "team-Pack_Modpack",
    })

    local manifest = shellSmoke.buildManifest({
        rootDir = root,
        libDir = "Lib",
    })

    lu.assertTrue(manifest.allowEmpty)
    lu.assertEquals(manifest.packId, "test-pack")
    lu.assertEquals(#manifest.modules, 0)
    lu.assertNil(manifest.coordinator)
end

function TestShellSmoke.testBuildManifestRejectsModuleTeamMismatch()
    local root = makeTempDir()
    writeCoordinator(root)
    writePackage(root, "Submodules/other-Module", "other", "Module")
    writeGitmodules(root, {
        "team-Pack_Modpack",
        "Submodules/other-Module",
    })

    lu.assertErrorMsgContains(
        "package.namespace must match coordinator namespace team",
        function()
            shellSmoke.buildManifest({ rootDir = root })
        end
    )
end
