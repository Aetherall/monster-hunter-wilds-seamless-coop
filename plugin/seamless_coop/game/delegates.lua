-- Who is subscribed to a delegate of the scene transition: its invocation
-- entries read from memory (count at +0x10, then 0x18-byte entries
-- {target, function, method} from +0x18). Bounded to a live delegate.

local managers = require("seamless_coop.game.managers")

local M = {}

---@param address integer
---@return integer?
local function qword(address)
    local v = sdk.to_valuetype(address, "System.UInt64")
    return v and v:read_qword(0)
end

-- How many entries the delegate at `base` has; 0 when that is no live
-- delegate's count.
---@param base integer
---@return integer
local function entry_count(base)
    local count = qword(base + 0x10)
    if type(count) ~= "number" then return 0 end
    count = count & 0xffffffff
    if count > 64 then return 0 end
    return count
end

---@param delegate REManagedObject?
---@return string[]
function M.entries(delegate)
    if delegate == nil then return {} end
    local base = delegate:get_address()
    local out = {}
    for i = 0, entry_count(base) - 1 do
        out[#out + 1] = string.format("0x%x", qword(base + 0x18 + 0x18 * i + 8) or 0)
    end
    return out
end

local function transition()
    return managers.single("app.GameFlowManager"):get_field("_GameJumper"):get_field("_GameSceneTransition")
end

local LISTS = { "LoadingEvent_UnLoadBefore", "LoadingEvent_LoadBefore", "LoadingEvent_WaitInstantiateBefore",
    "LoadingEvent_LoadAfter", "LoadBeforeEvent", "LoadStartEvent", "LoadEndEvent", "SceneLoadEndEvent",
    "SceneLoadFadeInEvent", "BeforeInstantiateEvent" }

---@param method REMethodDefinition
---@return boolean
function M.waits(method)
    local wanted = string.format("0x%x", sdk.to_int64(method:get_function()))
    local t = transition()
    for _, name in ipairs(LISTS) do
        for _, address in ipairs(M.entries(t:get_field(name))) do
            if address == wanted then return true end
        end
    end
    return false
end

-- The load's last event, for whoever waits on it.
function M.fade_in()
    local event = transition():get_field("SceneLoadFadeInEvent")
    if event ~= nil and #M.entries(event) > 0 then event:call("Invoke") end
end

return M
