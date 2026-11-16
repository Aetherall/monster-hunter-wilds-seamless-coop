-- Hooks on the game's methods. A hook can't be removed, so each is made
-- once per game run and calls the handlers of the modules loaded now: a
-- reload replaces the handlers, the hooks stay.

local memory = require("seamless_coop.base.memory")
local journal = require("seamless_coop.base.journal")

---@class sq.Handler
---@field pre (fun(args: HookArgs): sdk.PreHookResult?)?
---@field post (fun(retval: lightuserdata): lightuserdata?)?

---@class sq.Hooks.Kept
---@field hooked table<string, boolean>
---@field handlers table<string, sq.Handler>
---@field failed table<string, boolean>
---@type sq.Hooks.Kept
local kept = memory.keep("hooks", { hooked = {}, handlers = {}, failed = {} })

local Hooks = {}

-- A handler that fails is journaled once and the game goes on.
---@param name string
---@param err any
local function failed(name, err)
    if kept.failed[name] then return end
    kept.failed[name] = true
    journal.later("error", "%s: %s", name, err)
end

---@param key string
---@param args HookArgs
---@return sdk.PreHookResult?
local function run_pre(key, args)
    local handler = kept.handlers[key]
    if handler == nil or handler.pre == nil then return nil end
    local ok, result = pcall(handler.pre, args)
    if ok then return result end
    failed(key, result)
    return nil
end

---@param key string
---@param retval lightuserdata
---@return lightuserdata
local function run_post(key, retval)
    local handler = kept.handlers[key]
    if handler == nil or handler.post == nil then return retval end
    ---@type boolean, any
    local ok, result = pcall(handler.post, retval)
    if not ok then
        failed(key .. " (post)", result)
        return retval
    end
    return result or retval
end

-- `pre(args)` runs before `method` of `type_name` and may return
-- sdk.PreHookResult.SKIP_ORIGINAL; `post(retval)` runs after it and may
-- return another value.
---@param type_name string
---@param method_name string
---@param pre (fun(args: HookArgs): sdk.PreHookResult?)?
---@param post (fun(retval: lightuserdata): lightuserdata?)?
---@return boolean hooked
function Hooks.on(type_name, method_name, pre, post)
    local key = type_name .. "." .. method_name
    if kept.handlers[key] ~= nil then journal.note("error", "two handlers for %s: the later one kept", key) end
    kept.handlers[key] = { pre = pre, post = post }
    if kept.hooked[key] then return true end
    local td = sdk.find_type_definition(type_name)
    local method = td and td:get_method(method_name)
    if method == nil then
        journal.note("error", "no method %s", key)
        return false
    end
    kept.hooked[key] = true
    sdk.hook(method, function(args) return run_pre(key, args) end, function(retval) return run_post(key, retval) end)
    return true
end

-- The handlers of an earlier load of the modules, before the new ones
-- claim their hooks.
function Hooks.forget() kept.handlers = {} end

return Hooks
