local deps = ...
local integrationRegistry = deps.integrationRegistry

-- Hot-reload-stable integration provider buckets.
local providers = integrationRegistry.providers

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

local function getPreferredProvider(id)
    local bucket = getBucket(id, false)
    if not bucket then
        return nil, nil
    end

    for index = #bucket.order, 1, -1 do
        local providerId = bucket.order[index]
        local api = bucket.providers[providerId]
        if api ~= nil then
            return api, providerId
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

local function setProvider(id, providerId, api, ownerId, ownerToken)
    local bucket = getBucket(id, true)
    insertProviderOrder(bucket, providerId)
    bucket.providers[providerId] = api
    bucket.ownerIds[providerId] = ownerId
    bucket.ownerTokens[providerId] = ownerToken
    return api
end

local function getProviderOwnerId(id, providerId)
    local bucket = getBucket(id, false)
    return bucket and bucket.ownerIds and bucket.ownerIds[providerId] or nil
end

local function getProviderOwnerToken(id, providerId)
    local bucket = getBucket(id, false)
    return bucket and bucket.ownerTokens and bucket.ownerTokens[providerId] or nil
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
}
