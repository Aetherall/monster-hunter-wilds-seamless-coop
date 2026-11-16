-- The log feed on the right of the screen (GUI020100): our text in it,
-- and its one shortcut (Y).
--
-- The game's shortcut is a System.Action that GUI020100.callbackOther
-- (slot 1) invokes. Lua makes no delegate that runs Lua: the action stored
-- is an empty System.Action, there for the game to show the prompt and
-- enable the button; the press is caught elsewhere (offer.lua). The empty
-- action must never be invoked.

local journal = require("seamless_coop.base.journal")
local memory = require("seamless_coop.base.memory")
local managers = require("seamless_coop.game.managers")
local Screens = require("seamless_coop.game.screens")

---@class sq.Feed.Kept
---@field placeholder REManagedObject?
---@type sq.Feed.Kept
local kept = memory.keep("feed", {})

---@class sq.Feed
---@field private screen REManagedObject
local Feed = {}
Feed.__index = Feed

---@param screen REManagedObject?
---@return sq.Feed?
function Feed.wrap(screen)
    if screen == nil then return nil end
    ---@type sq.Feed
    local self = setmetatable({}, Feed)
    self.screen = screen
    return self
end

---@return sq.Feed?
function Feed.find() return Feed.wrap(Screens.named("GUI020100")()) end

---@return REManagedObject
local function placeholder()
    local action = kept.placeholder or sdk.create_instance("System.Action"):add_ref()
    kept.placeholder = action
    return action
end

---@private
---@return REManagedObject?
function Feed:shortcut() return self.screen:get_field("<_JustTimingShortcutAction>k__BackingField") end

---@return boolean
function Feed:has_shortcut() return self:shortcut() ~= nil end

-- Ours while the feed's shortcut is the action we stored; the game's own
-- (quest results, map logs) replaces it and our offer is gone.
---@return boolean
function Feed:shortcut_is_ours()
    local action, ours = self:shortcut(), kept.placeholder
    return action ~= nil and ours ~= nil and action:get_address() == ours:get_address()
end

---@param prompt string
function Feed:take_shortcut(prompt)
    self.screen:call("setJustTimingShortcutAction(System.Action, System.Func`1<System.Boolean>)", placeholder(), nil)
    local parts = self.screen:get_field("<PartsJust>k__BackingField")
    parts:call("start(System.Guid)", ValueType.new(sdk.find_type_definition("System.Guid")))
    parts:get_field("<_TextJust>k__BackingField"):call("set_Message(System.String)", prompt)
end

-- Our shortcut removed; the game's own is left alone.
function Feed:release_shortcut()
    if not self:shortcut_is_ours() then return end
    self.screen:call("clearJustTimingShortcutAction()")
    local parts = self.screen:get_field("<PartsJust>k__BackingField")
    if parts then parts:call("end()") end
end

-- Inside the game's frame.
---@param text string
function Feed.say(text)
    managers.single("app.ChatManager"):call("addSystemLog(System.String)", text)
    journal.note("notice", "%s", text)
end

return Feed
