local deps = ...

local fallbackUi = deps.fallbackUi
local hooks = deps.hooks
local shared = deps.shared
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
---@field hooks AuthorHooks
---@field shared AuthorShared
---@field mutation AuthorMutation
---@field overlays AuthorOverlays
---@field activate fun(): boolean, string|nil

---@class AuthorHooks
---@field wrap fun(path: string, keyOrHandler: string|function, maybeHandler: function|nil): nil
---@field override fun(path: string, keyOrReplacement: string|function, maybeReplacement: function|nil): nil
---@field contextWrap fun(path: string, keyOrContext: string|function, maybeContext: function|nil): nil

---@class AuthorShared
---@field data AuthorSharedData
---@field listen fun(id: string, eventName: string, callback: fun(payload: any)): table
---@field emit fun(id: string, eventName: string, payload: any): boolean, integer|string

---@class AuthorSharedData
---@field owner fun(name: string, opts: table): boolean
---@field reader fun(name: string, opts: table): boolean

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
        hooks = hooks.create(host),
        shared = shared.create(host),
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
