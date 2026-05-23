local deps = ...

local rom = deps.rom
local logging = deps.logging

local function expectedMessage(expectedType, optional)
    local expected = "a " .. expectedType
    if optional then
        expected = "nil or " .. expected
    end
    return expected
end

local function validateBoundaryValue(label, value, expectedType, optional)
    if value == nil and optional then
        return nil
    end
    if type(value) ~= expectedType then
        logging.violate("game_deps.invalid_boundary", "gameDeps." .. label .. " must be " .. expectedMessage(expectedType, optional))
    end
    return value
end

local function readGameGlobal(name)
    local game = validateBoundaryValue("rom.game", rom.game, "table", false)
    return game[name]
end

local function readOptionalGameGlobal(name, expectedType)
    return validateBoundaryValue(name, readGameGlobal(name), expectedType, true)
end

local function readRequiredGameGlobal(name, expectedType)
    return validateBoundaryValue(name, readGameGlobal(name), expectedType, false)
end

local function callGameGlobalFunction(name, ...)
    return readRequiredGameGlobal(name, "function")(...)
end

local function callRomGameFunction(name, ...)
    local game = validateBoundaryValue("rom.game", rom.game, "table", false)
    local callback = validateBoundaryValue("rom.game." .. name, game[name], "function", false)
    return callback(...)
end

local gameDeps = {
    cache = {
        CurrentRun = function()
            return readOptionalGameGlobal("CurrentRun", "table")
        end,
    },

    runData = {
        SetupRunData = function()
            return callRomGameFunction("SetupRunData")
        end,
    },

    overlays = {
        ScreenData = function()
            return readOptionalGameGlobal("ScreenData", "table")
        end,

        HUDScreen = function()
            return readOptionalGameGlobal("HUDScreen", "table")
        end,

        ShowingCombatUI = function()
            return readOptionalGameGlobal("ShowingCombatUI", "boolean")
        end,

        ModifyTextBox = function(args)
            return callGameGlobalFunction("ModifyTextBox", args)
        end,

        SetAlpha = function(args)
            return callGameGlobalFunction("SetAlpha", args)
        end,

        CreateComponentFromData = function(componentData, data)
            return callGameGlobalFunction("CreateComponentFromData", componentData, data)
        end,

        Destroy = function(args)
            return callGameGlobalFunction("Destroy", args)
        end,
    },
}

return gameDeps
