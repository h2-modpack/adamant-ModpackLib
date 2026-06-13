local source = debug.getinfo(1, "S").source
local harnessDir = source:sub(1, 1) == "@"
    and source:sub(2):match("^(.*)[/\\][^/\\]+$")
    or "tests/harness"
local smokeRunner = dofile(harnessDir .. "/smoke_runner.lua")

local ShellSmoke = {}

local function joinPath(rootDir, path)
    if rootDir == nil or rootDir == "" or rootDir == "." then
        return path
    end
    return rootDir .. "/" .. path
end

local function readFile(path)
    local file = io.open(path, "r")
    if not file then
        error("could not read " .. path, 3)
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function parseGitmodulePaths(rootDir)
    local paths = {}
    for line in readFile(joinPath(rootDir, ".gitmodules")):gmatch("[^\r\n]+") do
        local path = line:match("^%s*path%s*=%s*(.-)%s*$")
        if path then
            local normalizedPath = path:gsub("\\", "/")
            table.insert(paths, normalizedPath)
        end
    end
    table.sort(paths)
    return paths
end

local function parseLuaString(text, name, path)
    local value = text:match("%f[%w_]" .. name .. "%f[^%w_]%s*=%s*['\"]([^'\"]+)['\"]")
    if not value then
        error(path .. " must define " .. name, 3)
    end
    return value
end

local function parseTomlString(text, name, path)
    local value = text:match("%f[%w_]" .. name .. "%f[^%w_]%s*=%s*\"([^\"]+)\"")
    if not value then
        error(path .. " must define package." .. name, 3)
    end
    return value
end

local function readPackage(rootDir, repoPath)
    local path = repoPath .. "/thunderstore.toml"
    local text = readFile(joinPath(rootDir, path))
    local namespace = parseTomlString(text, "namespace", path)
    local name = parseTomlString(text, "name", path)
    return {
        namespace = namespace,
        name = name,
        pluginGuid = namespace .. "-" .. name,
    }
end

local function findCoordinator(rootDir, paths)
    local coordinator
    for _, repoPath in ipairs(paths) do
        if not repoPath:match("^Submodules/") then
            local ok, package = pcall(readPackage, rootDir, repoPath)
            if ok and package.name:match("_Modpack$") then
                if coordinator then
                    error("multiple coordinator packages found in .gitmodules", 3)
                end
                coordinator = {
                    path = repoPath,
                    package = package,
                }
            end
        end
    end
    if not coordinator then
        error("no coordinator package found in .gitmodules", 3)
    end
    return coordinator
end

local function buildModules(rootDir, paths, packId, team)
    local modules = {}
    for _, repoPath in ipairs(paths) do
        if repoPath:match("^Submodules/") then
            local package = readPackage(rootDir, repoPath)
            if package.namespace ~= team then
                error(repoPath .. " package.namespace must match coordinator namespace " .. team, 3)
            end
            table.insert(modules, {
                pluginGuid = package.pluginGuid,
                moduleSrcDir = joinPath(rootDir, repoPath .. "/src"),
                fixturePath = joinPath(rootDir, repoPath .. "/tests/smoke_env.lua"),
                expectedPackId = packId,
                expectedModuleId = package.name,
                moduleId = package.name,
            })
        end
    end
    return modules
end

function ShellSmoke.buildManifest(opts)
    opts = opts or {}
    local rootDir = opts.rootDir or "."
    local paths = parseGitmodulePaths(rootDir)
    local coordinator = findCoordinator(rootDir, paths)
    local mainPath = coordinator.path .. "/src/main.lua"
    local packId = parseLuaString(readFile(joinPath(rootDir, mainPath)), "PACK_ID", mainPath)
    local libDir = opts.libDir or "adamant-ModpackLib"
    local modules = buildModules(rootDir, paths, packId, coordinator.package.namespace)

    local manifest = {
        allowEmpty = true,
        libSrcDir = joinPath(rootDir, libDir .. "/src"),
        packId = packId,
        modules = modules,
    }

    if #modules > 0 then
        manifest.coordinator = {
            pluginGuid = coordinator.package.pluginGuid,
            srcDir = joinPath(rootDir, coordinator.path .. "/src"),
        }
    end

    return manifest
end

function ShellSmoke.run(opts)
    local manifest = ShellSmoke.buildManifest(opts)
    local results = smokeRunner.assertManifest(manifest)
    print(string.format(
        "Smoke passed: %d module entrypoints, %d coordinator pipeline.",
        #manifest.modules,
        manifest.coordinator and 1 or 0
    ))
    return results
end

return ShellSmoke
