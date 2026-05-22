local deps = ...

local cache = deps.cache
local fallbackUi = deps.fallbackUi
local hooks = deps.hooks
local integrations = deps.integrations
local mutation = deps.mutation
local overlays = deps.overlays

local authorHost = {}

---@class AuthorHost
---@field isEnabled fun(): boolean
---@field getHostId fun(): string
---@field getModuleId fun(): string
---@field getPackId fun(): string|nil
---@field getMeta fun(): table
---@field log fun(fmt: string, ...): nil
---@field logIf fun(fmt: string, ...): nil
---@field fallbackUi AuthorFallbackUi
---@field cache AuthorCache
---@field hooks AuthorHooks
---@field integrations AuthorIntegrations
---@field mutation AuthorMutation
---@field overlays AuthorOverlays
---@field activate fun(): boolean, string|nil

---@class AuthorHooks
---@field wrap fun(path: string, keyOrHandler: string|function, maybeHandler: function|nil): nil
---@field override fun(path: string, keyOrReplacement: string|function, maybeReplacement: function|nil): nil
---@field contextWrap fun(path: string, keyOrContext: string|function, maybeContext: function|nil): nil

---@class AuthorIntegrationRegistration
---@field providerId string
---@field methods table<string, AuthorIntegrationMethod>

---@class AuthorIntegrationMethod
---@field reads string[]|nil
---@field handler fun(scope: IntegrationReadScope, ...): any

---@class IntegrationReadScope
---@field read fun(alias: string, ...): any
---@field get fun(alias: string): StorageField|StorageTableStagedState|nil
---@field isEnabled fun(): boolean

---@class AuthorIntegrations
---@field register fun(id: string, opts: AuthorIntegrationRegistration): table
---@field invoke fun(id: string, methodName: string, fallback: any, ...): any, string|nil

---@class AuthorMutation
---@field patch fun(callback: fun(plan: table, host: AuthorHost, store: Store)): nil

---@class AuthorOverlays
---@field order table<string, integer>
---@field createLine fun(name: string, spec: table): nil
---@field createTable fun(name: string, spec: table): nil
---@field onCommit fun(callback: function): nil
---@field onInterval fun(name: string, seconds: number, callback: function, opts: table|nil): nil
---@field afterHook fun(path: string, callback: function): nil

---@class AuthorFallbackUi
---@field attachGuiOnce fun(register: fun(ui: FallbackUiBridge)): boolean

---@class AuthorCache
---@field currentRun AuthorCurrentRunCache
---@field persistent AuthorPersistentCache

---@class AuthorCurrentRunCache
---@field get fun(key: string, factory: (fun(): table)|nil): table|nil
---@field peek fun(key: string): table|nil
---@field clear fun(key: string): boolean

---@class AuthorPersistentCache
---@field read fun(key: string, defaultValue: boolean|number|string|nil): boolean|number|string|nil
---@field write fun(key: string, value: boolean|number|string): boolean
---@field clear fun(key: string): boolean
---@field has fun(key: string): boolean

---@param host ModuleHost
---@return AuthorHost host Module-safe projection of the ModuleHost surface.
function authorHost.create(host)
    return {
        isEnabled = host.isEnabled,
        getHostId = host.getHostId,
        getModuleId = host.getModuleId,
        getPackId = host.getPackId,
        getMeta = host.getMeta,
        activate = host.activate,
        fallbackUi = fallbackUi.create(host),
        cache = cache.create(host),
        hooks = hooks.create(host),
        integrations = integrations.create(host),
        mutation = mutation.create(host),
        overlays = overlays.create(host),
        log = function(fmt, ...)
            return host.log(fmt, ...)
        end,
        logIf = function(fmt, ...)
            return host.logIf(fmt, ...)
        end,
    }
end

return authorHost
