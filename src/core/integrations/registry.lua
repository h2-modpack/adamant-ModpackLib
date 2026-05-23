local deps = ...
local integrationRegistry = deps.integrationRegistry

-- Hot-reload-stable integration provider buckets.
local providers = integrationRegistry.providers
local listeners = integrationRegistry.listeners

local function getRegistry()
    return providers
end

local function getBucket(id, create)
    local bucket = providers[id]
    if not bucket and create then
        bucket = {
            providers = {},
            ownerIds = {},
            ownerTokens = {},
            order = {},
        }
        providers[id] = bucket
    end
    if bucket then
        bucket.ownerIds = bucket.ownerIds or {}
        bucket.ownerTokens = bucket.ownerTokens or {}
    end
    return bucket
end

local function removeProviderFromBucket(bucket, providerId, expectedOwnerId, expectedOwnerToken)
    if not bucket or bucket.providers[providerId] == nil then
        return false
    end
    if expectedOwnerId ~= nil and bucket.ownerIds and bucket.ownerIds[providerId] ~= expectedOwnerId then
        return false
    end
    if expectedOwnerToken ~= nil and bucket.ownerTokens and bucket.ownerTokens[providerId] ~= expectedOwnerToken then
        return false
    end

    bucket.providers[providerId] = nil
    if bucket.ownerIds then
        bucket.ownerIds[providerId] = nil
    end
    if bucket.ownerTokens then
        bucket.ownerTokens[providerId] = nil
    end
    for index, currentProviderId in ipairs(bucket.order) do
        if currentProviderId == providerId then
            table.remove(bucket.order, index)
            break
        end
    end

    return true
end

local function pruneBucket(id, bucket)
    if bucket and #bucket.order == 0 then
        providers[id] = nil
    end
end

local function getPreferredProvider(id, predicate)
    local bucket = getBucket(id, false)
    if not bucket then
        return nil, nil
    end

    for index = #bucket.order, 1, -1 do
        local providerId = bucket.order[index]
        local provider = bucket.providers[providerId]
        if provider ~= nil and (predicate == nil or predicate(provider, providerId)) then
            return provider, providerId
        end
    end

    return nil, nil
end

local function getProviderOrderIndex(bucket, providerId)
    for index, currentProviderId in ipairs(bucket.order) do
        if currentProviderId == providerId then
            return index
        end
    end
    return nil
end

local function insertProviderOrder(bucket, providerId, index)
    if getProviderOrderIndex(bucket, providerId) then
        return
    end
    if index and index <= #bucket.order then
        table.insert(bucket.order, index, providerId)
    else
        table.insert(bucket.order, providerId)
    end
end

local function setProvider(id, providerId, provider, ownerId, ownerToken)
    local bucket = getBucket(id, true)
    insertProviderOrder(bucket, providerId)
    bucket.providers[providerId] = provider
    bucket.ownerIds[providerId] = ownerId
    bucket.ownerTokens[providerId] = ownerToken
    return provider
end

local function getProviderOwnerId(id, providerId)
    local bucket = getBucket(id, false)
    return bucket and bucket.ownerIds and bucket.ownerIds[providerId] or nil
end

local function getProviderOwnerToken(id, providerId)
    local bucket = getBucket(id, false)
    return bucket and bucket.ownerTokens and bucket.ownerTokens[providerId] or nil
end

local function getProviderForOwner(id, ownerId, predicate)
    local bucket = getBucket(id, false)
    if not bucket then
        return nil, nil
    end

    for index = #bucket.order, 1, -1 do
        local providerId = bucket.order[index]
        local provider = bucket.providers[providerId]
        if provider ~= nil
            and bucket.ownerIds
            and bucket.ownerIds[providerId] == ownerId
            and (predicate == nil or predicate(provider, providerId))
        then
            return provider, providerId
        end
    end

    return nil, nil
end

local function listProvidersForOwner(ownerId)
    local ids = {}
    for id in pairs(providers) do
        ids[#ids + 1] = id
    end
    table.sort(ids)

    local result = {}
    for _, id in ipairs(ids) do
        local bucket = providers[id]
        if bucket and bucket.ownerIds then
            for _, providerId in ipairs(bucket.order) do
                local provider = bucket.providers[providerId]
                if provider ~= nil and bucket.ownerIds[providerId] == ownerId then
                    result[#result + 1] = {
                        id = id,
                        providerId = providerId,
                        provider = provider,
                    }
                end
            end
        end
    end
    return result
end

local function getListenerRoot(id, create)
    local root = listeners[id]
    if not root and create then
        root = {}
        listeners[id] = root
    end
    return root
end

local function getListenerBucket(id, eventName, create)
    local root = getListenerRoot(id, create)
    if not root then
        return nil
    end

    local bucket = root[eventName]
    if not bucket and create then
        bucket = {
            listeners = {},
            ownerIds = {},
            ownerTokens = {},
            order = {},
        }
        root[eventName] = bucket
    end
    return bucket
end

local function getListenerOrderIndex(bucket, key)
    for index, currentKey in ipairs(bucket.order) do
        if currentKey == key then
            return index
        end
    end
    return nil
end

local function insertListenerOrder(bucket, key, index)
    if getListenerOrderIndex(bucket, key) then
        return
    end
    if index and index <= #bucket.order then
        table.insert(bucket.order, index, key)
    else
        table.insert(bucket.order, key)
    end
end

local function setListener(id, eventName, key, listener, ownerId, ownerToken)
    local bucket = getListenerBucket(id, eventName, true)
    insertListenerOrder(bucket, key)
    bucket.listeners[key] = listener
    bucket.ownerIds[key] = ownerId
    bucket.ownerTokens[key] = ownerToken
    return listener
end

local function removeListenerFromBucket(bucket, key, expectedOwnerId, expectedOwnerToken)
    if not bucket or bucket.listeners[key] == nil then
        return false
    end
    if expectedOwnerId ~= nil and bucket.ownerIds[key] ~= expectedOwnerId then
        return false
    end
    if expectedOwnerToken ~= nil and bucket.ownerTokens[key] ~= expectedOwnerToken then
        return false
    end

    bucket.listeners[key] = nil
    bucket.ownerIds[key] = nil
    bucket.ownerTokens[key] = nil
    for index, currentKey in ipairs(bucket.order) do
        if currentKey == key then
            table.remove(bucket.order, index)
            break
        end
    end
    return true
end

local function pruneListenerBucket(id, eventName, bucket)
    if bucket and #bucket.order == 0 then
        local root = getListenerRoot(id, false)
        if root then
            root[eventName] = nil
            if next(root) == nil then
                listeners[id] = nil
            end
        end
    end
end

return {
    getRegistry = getRegistry,
    getBucket = getBucket,
    removeProviderFromBucket = removeProviderFromBucket,
    pruneBucket = pruneBucket,
    getPreferredProvider = getPreferredProvider,
    getProviderOrderIndex = getProviderOrderIndex,
    insertProviderOrder = insertProviderOrder,
    setProvider = setProvider,
    getProviderOwnerId = getProviderOwnerId,
    getProviderOwnerToken = getProviderOwnerToken,
    getProviderForOwner = getProviderForOwner,
    listProvidersForOwner = listProvidersForOwner,
    getListenerBucket = getListenerBucket,
    getListenerOrderIndex = getListenerOrderIndex,
    insertListenerOrder = insertListenerOrder,
    setListener = setListener,
    removeListenerFromBucket = removeListenerFromBucket,
    pruneListenerBucket = pruneListenerBucket,
}
