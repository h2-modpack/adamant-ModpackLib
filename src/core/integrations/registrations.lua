local deps = ...

local logging = deps.logging
local registry = deps.registry
local readScope = deps.readScope
local constants = deps.constants
local registrations = {}

local function validateIntegrationId(context, id)
    if type(id) ~= "string" or id == "" then
        logging.violate("integrations.invalid_args", "%s: id must be a non-empty string", context)
    end
end

local function validateProviderId(context, providerId)
    if type(providerId) ~= "string" or providerId == "" then
        logging.violate("integrations.invalid_args", "%s: providerId must be a non-empty string", context)
    end
end

local function validateMethodName(context, methodName)
    if type(methodName) ~= "string" or methodName == "" then
        logging.violate("integrations.invalid_args", "%s: method name must be a non-empty string", context)
    end
end

local function validateMethods(context, methods)
    if type(methods) ~= "table" then
        logging.violate("integrations.invalid_args", "%s: methods must be a table", context)
    end
end

local function validateEventName(context, eventName)
    if type(eventName) ~= "string" or eventName == "" then
        logging.violate("integrations.invalid_args", "%s: event name must be a non-empty string", context)
    end
end

local function createRegistrationSet()
    return {
        entries = {},
        byKey = {},
        listenerEntries = {},
    }
end

local function hasRegistrationEntries(registrationSet)
    return registrationSet
        and (#(registrationSet.entries or {}) > 0 or #(registrationSet.listenerEntries or {}) > 0)
end

local function makeNoopReceipt()
    return {
        commit = function()
            return true, nil
        end,
        dispose = function()
            return true, nil
        end,
    }
end

local function ensureHostRegistrations(state)
    if not state.integrationRegistrations then
        state.integrationRegistrations = createRegistrationSet()
    end
    return state.integrationRegistrations
end

local function normalizeReads(context, methodName, reads, stagedState)
    if reads == nil then
        return {}
    end
    if type(reads) ~= "table" then
        logging.violate("integrations.invalid_args", "%s.%s: reads must be a list of storage aliases", context, methodName)
    end

    local normalized = {}
    local seen = {}
    local count = 0
    for index, alias in ipairs(reads) do
        count = index
        if type(alias) ~= "string" or alias == "" then
            logging.violate(
                "integrations.invalid_args",
                "%s.%s: reads[%s] must be a non-empty storage alias",
                context,
                methodName,
                tostring(index))
        end
        if stagedState.getAliasSchema(alias) == nil then
            logging.violate(
                "integrations.invalid_args",
                "%s.%s: reads alias '%s' is not declared storage",
                context,
                methodName,
                alias)
        end
        if not seen[alias] then
            seen[alias] = true
            normalized[#normalized + 1] = alias
        end
    end
    for key in pairs(reads) do
        if type(key) ~= "number" or key < 1 or key > count or math.floor(key) ~= key then
            logging.violate(
                "integrations.invalid_args",
                "%s.%s: reads must be an array of storage aliases",
                context,
                methodName)
        end
    end
    return normalized
end

local function normalizeEvents(context, events)
    if events == nil then
        return {}
    end
    if type(events) ~= "table" then
        logging.violate("integrations.invalid_args", "%s: events must be a map of eventName = true", context)
    end

    local normalized = {}
    for eventName, enabled in pairs(events) do
        validateEventName(context, eventName)
        if eventName == constants.PROVIDER_CHANGED_EVENT then
            logging.violate(
                "integrations.invalid_args",
                "%s: event '%s' is reserved by Lib",
                context,
                tostring(eventName))
        end
        if enabled ~= true then
            logging.violate(
                "integrations.invalid_args",
                "%s: event '%s' must be declared as true",
                context,
                tostring(eventName))
        end
        normalized[eventName] = true
    end
    return normalized
end

local function createProvider(record, host, id, opts)
    local context = "host.integrations.provide(" .. tostring(id) .. ")"
    validateMethods(context, opts.methods)

    local provider = {
        isEnabled = function()
            return host.isEnabled()
        end,
        methods = {},
        events = normalizeEvents(context, opts.events),
    }
    for methodName, methodOpts in pairs(opts.methods) do
        validateMethodName(context, methodName)
        if type(methodOpts) ~= "table" then
            logging.violate("integrations.invalid_args", "%s.%s: method must be a table", context, methodName)
        end
        if type(methodOpts.handler) ~= "function" then
            logging.violate("integrations.invalid_args", "%s.%s: handler must be a function", context, methodName)
        end

        local methodContext = context .. "." .. methodName
        provider.methods[methodName] = {
            handler = methodOpts.handler,
            scope = readScope.create({
                stagedState = record.stagedState,
                reads = normalizeReads(context, methodName, methodOpts.reads, record.stagedState),
                context = methodContext,
            }),
        }
    end

    return provider
end

local function createListener(host, callback)
    return {
        callback = callback,
        isEnabled = function()
            return host.isEnabled()
        end,
    }
end

local function recordStagedRegistration(registrationSet, id, providerId, provider)
    local key = id .. "\0" .. providerId
    local entry = registrationSet.byKey[key]
    if not entry then
        entry = {
            id = id,
            providerId = providerId,
            provider = provider,
        }
        registrationSet.byKey[key] = entry
        registrationSet.entries[#registrationSet.entries + 1] = entry
    else
        entry.provider = provider
    end
    return provider
end

local function recordStagedListener(registrationSet, id, eventName, listener)
    registrationSet.listenerEntries = registrationSet.listenerEntries or {}
    registrationSet.listenerEntries[#registrationSet.listenerEntries + 1] = {
        id = id,
        eventName = eventName,
        listener = listener,
    }
    return listener
end

function registrations.stageAuthorRegistration(record, host, id, opts)
    local context = "host.integrations.provide"
    validateIntegrationId(context, id)
    if type(opts) ~= "table" then
        logging.violate("integrations.invalid_args", "%s: opts must be a table", context)
    end
    validateProviderId(context, opts.providerId)
    return recordStagedRegistration(ensureHostRegistrations(record), id, opts.providerId, createProvider(record, host, id, opts))
end

function registrations.stageAuthorListener(record, host, id, eventName, callback)
    local context = "host.integrations.listen"
    validateIntegrationId(context, id)
    validateEventName(context, eventName)
    if type(callback) ~= "function" then
        logging.violate("integrations.invalid_args", "%s: callback must be a function", context)
    end
    return recordStagedListener(ensureHostRegistrations(record), id, eventName, createListener(host, callback))
end

function registrations.install(ownerId, hostRegistrations)
    if not hasRegistrationEntries(hostRegistrations) then
        return makeNoopReceipt()
    end

    local install = {
        ownerId = ownerId,
        ownerToken = {},
        entries = {},
        byKey = {},
        listenerEntries = {},
        previous = {},
        previousListeners = {},
        committed = false,
        disposed = false,
    }

    for _, entry in ipairs(hostRegistrations.entries) do
        recordStagedRegistration(install, entry.id, entry.providerId, entry.provider)
    end
    for _, entry in ipairs(hostRegistrations.listenerEntries or {}) do
        recordStagedListener(install, entry.id, entry.eventName, entry.listener)
    end

    return {
        commit = function()
            if install.disposed or install.committed then
                return true, nil
            end
            for _, entry in ipairs(install.entries) do
                local bucket = registry.getBucket(entry.id, false)
                local key = entry.id .. "\0" .. entry.providerId
                install.previous[key] = {
                    id = entry.id,
                    providerId = entry.providerId,
                    existed = bucket and bucket.providers[entry.providerId] ~= nil or false,
                    provider = bucket and bucket.providers[entry.providerId] or nil,
                    ownerId = bucket and registry.getProviderOwnerId(entry.id, entry.providerId) or nil,
                    ownerToken = bucket and registry.getProviderOwnerToken(entry.id, entry.providerId) or nil,
                    orderIndex = bucket and registry.getProviderOrderIndex(bucket, entry.providerId) or nil,
                }
                registry.setProvider(entry.id, entry.providerId, entry.provider, ownerId, install.ownerToken)
            end
            for index, entry in ipairs(install.listenerEntries) do
                local key = ownerId .. "\0" .. tostring(index)
                local bucket = registry.getListenerBucket(entry.id, entry.eventName, false)
                install.previousListeners[index] = {
                    id = entry.id,
                    eventName = entry.eventName,
                    key = key,
                    existed = bucket and bucket.listeners[key] ~= nil or false,
                    listener = bucket and bucket.listeners[key] or nil,
                    ownerId = bucket and bucket.ownerIds[key] or nil,
                    ownerToken = bucket and bucket.ownerTokens[key] or nil,
                    orderIndex = bucket and registry.getListenerOrderIndex(bucket, key) or nil,
                }
                registry.setListener(entry.id, entry.eventName, key, entry.listener, ownerId, install.ownerToken)
            end
            install.committed = true
            return true, nil
        end,
        dispose = function()
            if install.disposed then
                return true, nil
            end
            if install.committed then
                for index = #install.entries, 1, -1 do
                    local entry = install.entries[index]
                    local key = entry.id .. "\0" .. entry.providerId
                    local previous = install.previous[key]
                    local bucket = registry.getBucket(entry.id, previous and previous.existed or false)
                    if bucket
                        and registry.getProviderOwnerId(entry.id, entry.providerId) == install.ownerId
                        and registry.getProviderOwnerToken(entry.id, entry.providerId) == install.ownerToken
                    then
                        if previous and previous.existed then
                            bucket.providers[entry.providerId] = previous.provider
                            bucket.ownerIds[entry.providerId] = previous.ownerId
                            bucket.ownerTokens[entry.providerId] = previous.ownerToken
                            registry.insertProviderOrder(bucket, entry.providerId, previous.orderIndex)
                        else
                            registry.removeProviderFromBucket(
                                bucket,
                                entry.providerId,
                                install.ownerId,
                                install.ownerToken)
                            registry.pruneBucket(entry.id, bucket)
                        end
                    end
                end
                for index = #install.listenerEntries, 1, -1 do
                    local previous = install.previousListeners[index]
                    local bucket = registry.getListenerBucket(
                        previous.id,
                        previous.eventName,
                        previous and previous.existed or false)
                    if bucket
                        and bucket.ownerIds[previous.key] == install.ownerId
                        and bucket.ownerTokens[previous.key] == install.ownerToken
                    then
                        if previous and previous.existed then
                            bucket.listeners[previous.key] = previous.listener
                            bucket.ownerIds[previous.key] = previous.ownerId
                            bucket.ownerTokens[previous.key] = previous.ownerToken
                            registry.insertListenerOrder(bucket, previous.key, previous.orderIndex)
                        else
                            registry.removeListenerFromBucket(
                                bucket,
                                previous.key,
                                install.ownerId,
                                install.ownerToken)
                            registry.pruneListenerBucket(previous.id, previous.eventName, bucket)
                        end
                    end
                end
            end
            install.disposed = true
            return true, nil
        end,
    }
end

return registrations
