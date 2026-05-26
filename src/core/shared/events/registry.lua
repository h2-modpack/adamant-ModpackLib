local deps = ...
local eventRegistry = deps.eventRegistry

local listeners = eventRegistry.listeners

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
    getListenerBucket = getListenerBucket,
    getListenerOrderIndex = getListenerOrderIndex,
    insertListenerOrder = insertListenerOrder,
    setListener = setListener,
    removeListenerFromBucket = removeListenerFromBucket,
    pruneListenerBucket = pruneListenerBucket,
}
