local deps = ...

local logging = deps.logging
local values = deps.values

local compiler = {}

local StableIdentifierPattern = "^[A-Za-z][A-Za-z0-9_]*$"
local StableIdentifierDescription = "must start with a letter and contain only letters, digits, and underscores"

local function isStableIdentifier(value)
    return type(value) == "string" and string.match(value, StableIdentifierPattern) ~= nil
end

local function requireStableIdentifier(context, value)
    if not isStableIdentifier(value) then
        logging.violate("controls.invalid_field", "%s '%s' %s", context, tostring(value), StableIdentifierDescription)
    end
end

local function compareStrings(a, b)
    return a < b
end

local GeneratedPathSeparator = "-"

local function generatedName(controlName, ...)
    local parts = { "_", controlName }
    for index = 1, select("#", ...) do
        parts[#parts + 1] = GeneratedPathSeparator
        parts[#parts + 1] = tostring(select(index, ...))
    end
    return table.concat(parts)
end

local function normalizeViews(template)
    local views = {}
    if type(template.views) == "table" then
        for name, callback in pairs(template.views) do
            views[name] = callback
        end
    end
    if template.draw ~= nil then
        views.default = template.draw
    end
    return views
end

local function copyDescriptor(descriptor)
    local copy = values.deepCopy(descriptor)
    copy.key = nil
    return copy
end

local function rejectStatusField(controlName, fieldKey)
    local message = "controls cannot declare status storage; declare status at module level " ..
        "and pass the value into the control view"
    logging.violate("controls.invalid_field",
        "control '%s' field '%s': %s",
        tostring(controlName),
        tostring(fieldKey),
        message)
end

local function compileBitNodes(bits, controlName, parentKey, binding)
    if bits == nil then
        return nil
    end
    if type(bits) ~= "table" then
        logging.violate("controls.invalid_field", "control '%s' field '%s': bits must be a table",
            tostring(controlName), tostring(parentKey))
    end

    local compiled = {}
    binding.bitAliases = {}
    for index, bit in ipairs(bits) do
        if type(bit) ~= "table" then
            logging.violate("controls.invalid_field", "control '%s' field '%s' bit #%d must be a table",
                tostring(controlName), tostring(parentKey), index)
        end
        local key = bit.key or bit.alias
        requireStableIdentifier("control packed bit key", key)
        if bit.mode == "runtime" then
            rejectStatusField(controlName, parentKey .. GeneratedPathSeparator .. key)
        end
        local bitCopy = copyDescriptor(bit)
        bitCopy.alias = generatedName(controlName, parentKey, key)
        binding.bitAliases[key] = bitCopy.alias
        compiled[#compiled + 1] = bitCopy
    end
    return compiled
end

local function compileRowNodes(row, controlName, parentKey, binding)
    if row == nil then
        return nil
    end
    if type(row) ~= "table" then
        logging.violate("controls.invalid_field", "control '%s' field '%s': row must be a table",
            tostring(controlName), tostring(parentKey))
    end

    local compiled = {}
    binding.rowAliases = {}
    binding.rowBindings = {}
    for index, rowNode in ipairs(row) do
        if type(rowNode) ~= "table" then
            logging.violate("controls.invalid_field", "control '%s' field '%s' row #%d must be a table",
                tostring(controlName), tostring(parentKey), index)
        end
        local rowKey = rowNode.key or rowNode.alias
        requireStableIdentifier("control row field key", rowKey)
        if rowNode.mode == "runtime" then
            rejectStatusField(controlName, parentKey .. GeneratedPathSeparator .. rowKey)
        end
        local child = copyDescriptor(rowNode)
        child.alias = generatedName(controlName, parentKey, rowKey)
        local childBinding = {
            key = rowKey,
            alias = child.alias,
            type = child.type,
        }
        child.bits = compileBitNodes(child.bits, controlName, parentKey .. GeneratedPathSeparator .. rowKey, childBinding)
        binding.rowAliases[rowKey] = child.alias
        binding.rowBindings[rowKey] = childBinding
        compiled[#compiled + 1] = child
    end
    return compiled
end

local function compileStorageNodes(controlName, descriptors)
    if descriptors == nil then
        return {}, {}
    end
    if type(descriptors) ~= "table" then
        logging.violate("controls.invalid_field", "control '%s': storage(...) must return a table", tostring(controlName))
    end

    local storageNodes = {}
    local bindings = {}
    for index, descriptor in ipairs(descriptors) do
        if type(descriptor) ~= "table" then
            logging.violate("controls.invalid_field", "control '%s' storage #%d must be a table",
                tostring(controlName), index)
        end
        local key = descriptor.key or descriptor.alias
        requireStableIdentifier("control storage field key", key)
        if descriptor.mode == "runtime" then
            rejectStatusField(controlName, key)
        end
        if bindings[key] ~= nil then
            logging.violate("controls.duplicate_name", "control '%s' has duplicate field '%s'",
                tostring(controlName), tostring(key))
        end

        local node = copyDescriptor(descriptor)
        node.alias = generatedName(controlName, key)
        local binding = {
            key = key,
            alias = node.alias,
            type = node.type,
        }
        node.bits = compileBitNodes(node.bits, controlName, key, binding)
        if node.type == "table" then
            node.row = compileRowNodes(node.row, controlName, key, binding)
        end
        bindings[key] = binding
        storageNodes[#storageNodes + 1] = node
    end
    return storageNodes, bindings
end

function compiler.compile(bucket)
    bucket = bucket or {}
    local templates = bucket.templates or {}
    local instances = bucket.instances or {}
    local order = {}
    for _, name in ipairs(bucket.instanceOrder or {}) do
        order[#order + 1] = name
    end
    table.sort(order, compareStrings)

    local internalStorage = {}
    local catalog = {
        instances = {},
        order = order,
    }

    for _, name in ipairs(order) do
        local sourceInstance = instances[name]
        local templateName = sourceInstance and sourceInstance.template or nil
        local template = templates[templateName]
        if template == nil then
            logging.violate("controls.unknown_template", "control '%s' references unknown template '%s'",
                tostring(name), tostring(templateName))
        end

        local instance = values.deepCopy(sourceInstance)
        instance.name = name
        if type(template.prepare) == "function" then
            local ok, preparedOrErr, maybeErr = pcall(template.prepare, instance)
            if not ok then
                error(preparedOrErr, 0)
            end
            if preparedOrErr == nil then
                logging.violate("controls.invalid_declaration", "control '%s': %s",
                    tostring(name), tostring(maybeErr or "prepare returned nil"))
            end
            if type(preparedOrErr) ~= "table" then
                logging.violate("controls.invalid_declaration", "control '%s': prepare must return a table, got %s",
                    tostring(name), type(preparedOrErr))
            end
            instance = preparedOrErr
            instance.name = instance.name or name
        end

        local storageDescriptors = nil
        if type(template.storage) == "function" then
            storageDescriptors = template.storage(instance)
        elseif template.storage ~= nil then
            storageDescriptors = template.storage
        end
        local storageNodes, bindings = compileStorageNodes(name, storageDescriptors)
        for _, node in ipairs(storageNodes) do
            internalStorage[#internalStorage + 1] = node
        end

        catalog.instances[name] = {
            name = name,
            templateName = templateName,
            template = template,
            instance = instance,
            bindings = bindings,
            views = normalizeViews(template),
        }
    end

    return {
        storage = internalStorage,
        catalog = catalog,
    }
end

return compiler
