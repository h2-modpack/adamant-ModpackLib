local deps = ...

local rom = deps.rom
local logging = deps.logging

local function readGlobal(name)
    return rawget(_G, name)
end

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

local function readOptionalGlobal(name, expectedType)
    return validateBoundaryValue(name, readGlobal(name), expectedType, true)
end

local function readRequiredGlobal(name, expectedType)
    return validateBoundaryValue(name, readGlobal(name), expectedType, false)
end

local function callGlobalFunction(name, ...)
    return readRequiredGlobal(name, "function")(...)
end

local function callRomGameFunction(name, ...)
    local game = validateBoundaryValue("rom.game", rom.game, "table", false)
    local callback = validateBoundaryValue("rom.game." .. name, game[name], "function", false)
    return callback(...)
end

local gameDeps = {
    cache = {
        CurrentRun = function()
            return readOptionalGlobal("CurrentRun", "table")
        end,
    },

    runData = {
        SetupRunData = function()
            return callRomGameFunction("SetupRunData")
        end,
    },

    overlays = {
        ScreenData = function()
            return readOptionalGlobal("ScreenData", "table")
        end,

        HUDScreen = function()
            return readOptionalGlobal("HUDScreen", "table")
        end,

        ShowingCombatUI = function()
            return readOptionalGlobal("ShowingCombatUI", "boolean")
        end,

        ModifyTextBox = function(args)
            return callGlobalFunction("ModifyTextBox", args)
        end,

        SetAlpha = function(args)
            return callGlobalFunction("SetAlpha", args)
        end,

        CreateComponentFromData = function(componentData, data)
            return callGlobalFunction("CreateComponentFromData", componentData, data)
        end,

        Destroy = function(args)
            return callGlobalFunction("Destroy", args)
        end,
    },
}

return gameDeps
