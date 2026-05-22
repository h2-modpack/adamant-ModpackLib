local deps = ...
local overlayRegistry = deps.overlayRegistry

overlayRegistry.renderer = overlayRegistry.renderer or {}
overlayRegistry.renderer.textElements = overlayRegistry.renderer.textElements or {}
overlayRegistry.renderer.stackRows = overlayRegistry.renderer.stackRows or {}

overlayRegistry.uiSuppressors = overlayRegistry.uiSuppressors or {}
overlayRegistry.nextUiSuppressorId = overlayRegistry.nextUiSuppressorId or 0

overlayRegistry.retained = overlayRegistry.retained or {}
overlayRegistry.retained.tableRegistries = overlayRegistry.retained.tableRegistries or setmetatable({}, { __mode = "k" })
overlayRegistry.retained.explicitRegistries = overlayRegistry.retained.explicitRegistries or {}
overlayRegistry.retained.nextOwnerId = overlayRegistry.retained.nextOwnerId or 0
overlayRegistry.retained.intervalDriverRegistered = overlayRegistry.retained.intervalDriverRegistered == true

return overlayRegistry
