local deps = ...

local logging = deps.logging

local declarations = {}

local StableIdentifierPattern = "^[A-Za-z][A-Za-z0-9_]*$"
local StableIdentifierDescription = "must start with a letter and contain only letters, digits, and underscores"

local function isStableIdentifier(value)
    return type(value) == "string" and string.match(value, StableIdentifierPattern) ~= nil
end

local function requireStableIdentifier(context, value)
    if not isStableIdentifier(value) then
        logging.violate("controls.invalid_declaration", "%s '%s' %s", context, tostring(value), StableIdentifierDescription)
    end
end

local function validateTemplate(templateName, template)
    local hasDraw = template.draw ~= nil
    local hasViews = template.views ~= nil

    if template.prepare ~= nil and type(template.prepare) ~= "function" then
        logging.violate("controls.invalid_template", "controls template '%s': prepare must be a function", templateName)
    end
    if template.storage ~= nil and type(template.storage) ~= "function" and type(template.storage) ~= "table" then
        logging.violate("controls.invalid_template", "controls template '%s': storage must be a function or table",
            templateName)
    end
    if template.createRuntime ~= nil and type(template.createRuntime) ~= "function" then
        logging.violate("controls.invalid_template", "controls template '%s': createRuntime must be a function",
            templateName)
    end
    if template.createUi ~= nil and type(template.createUi) ~= "function" then
        logging.violate("controls.invalid_template", "controls template '%s': createUi must be a function", templateName)
    end
    if hasDraw and type(template.draw) ~= "function" then
        logging.violate("controls.invalid_template", "controls template '%s': draw must be a function", templateName)
    end
    if hasViews and type(template.views) ~= "table" then
        logging.violate("controls.invalid_template", "controls template '%s': views must be a table", templateName)
    end
    if not hasDraw and not hasViews then
        logging.violate("controls.invalid_template", "controls template '%s': draw or views.default is required", templateName)
    end
    if hasViews then
        local hasDefault = hasDraw or type(template.views.default) == "function"
        if not hasDefault then
            logging.violate("controls.invalid_template", "controls template '%s': views.default is required", templateName)
        end
        for viewName, callback in pairs(template.views) do
            requireStableIdentifier("controls template view", viewName)
            if type(callback) ~= "function" then
                logging.violate("controls.invalid_template",
                    "controls template '%s': view '%s' must be a function",
                    templateName,
                    tostring(viewName))
            end
        end
    end
end

function declarations.create()
    return {
        templates = {},
        templateOrder = {},
        instances = {},
        instanceOrder = {},
    }
end

function declarations.defineTemplates(bucket, templates)
    if type(templates) ~= "table" then
        logging.violate("controls.invalid_declaration", "module.controls.defineTemplates expects a table")
    end

    for name, template in pairs(templates) do
        requireStableIdentifier("controls template name", name)
        if bucket.templates[name] ~= nil then
            logging.violate("controls.duplicate_name", "duplicate controls template '%s'", tostring(name))
        end
        if type(template) ~= "table" then
            logging.violate("controls.invalid_template", "controls template '%s' must be a table", tostring(name))
        end
        validateTemplate(name, template)
        bucket.templates[name] = template
        bucket.templateOrder[#bucket.templateOrder + 1] = name
    end
end

function declarations.define(bucket, instances)
    if type(instances) ~= "table" then
        logging.violate("controls.invalid_declaration", "module.controls.define expects a table")
    end

    for name, instance in pairs(instances) do
        requireStableIdentifier("controls instance name", name)
        if bucket.instances[name] ~= nil then
            logging.violate("controls.duplicate_name", "duplicate control '%s'", tostring(name))
        end
        if type(instance) ~= "table" then
            logging.violate("controls.invalid_declaration", "control '%s' must be a table", tostring(name))
        end
        if type(instance.template) ~= "string" or instance.template == "" then
            logging.violate("controls.invalid_declaration", "control '%s' must declare a template", tostring(name))
        end
        requireStableIdentifier("controls instance template", instance.template)
        bucket.instances[name] = instance
        bucket.instanceOrder[#bucket.instanceOrder + 1] = name
    end
end

return declarations
