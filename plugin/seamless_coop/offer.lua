-- An action of ours offered on the feed's Y. Which offer stands is
-- decided elsewhere (policy.offers, offers.lua); this only shows one, and
-- tells how it ended.

local journal = require("seamless_coop.base.journal")
local hooks = require("seamless_coop.base.hooks")
local arg = require("seamless_coop.base.arg")
local tasks = require("seamless_coop.base.tasks")
local memory = require("seamless_coop.base.memory")
local Feed = require("seamless_coop.game.feed")
local note = journal.note

---@class sq.Offer.Kept
---@field offer sq.Offer?
---@type sq.Offer.Kept
local kept = memory.keep("offer", {})

-- GUIDef.BUTTON_SLOT of the feed's shortcut.
local SHORTCUT_SLOT = 1

---@class sq.Offer
---@field id string
---@field private action async fun()
---@field private lost fun()?
---@field private until_at number
local Offer = {}
Offer.__index = Offer

---@return sq.Offer?
function Offer.standing() return kept.offer end

---@private
function Offer.release()
    local feed = Feed.find()
    if feed ~= nil then feed:release_shortcut() end
end

-- Inside the game's frame. `text` goes to the feed, `prompt` next to the
-- Y button; `action` runs in a task when Y is pressed within `seconds`.
-- An offer replaces the shortcut up, ours or the game's (a map log's,
-- say); when the game takes the slot back, `lost` is called. False when
-- the feed is not on screen.
---@param id string
---@param text string
---@param prompt string
---@param seconds number
---@param action async fun()
---@param lost fun()?
---@return boolean shown
function Offer.make(id, text, prompt, seconds, action, lost)
    local feed = Feed.find()
    if feed == nil then return false end
    if kept.offer == nil and feed:has_shortcut() then note("notice", "offer %s replaces the game's shortcut", id) end
    Feed.say(text)
    feed:take_shortcut(prompt)
    ---@type sq.Offer
    local self = setmetatable({}, Offer)
    self.id, self.action, self.lost, self.until_at = id, action, lost, os.clock() + seconds
    kept.offer = self
    return true
end

-- Inside the game's frame.
function Offer:withdraw()
    Offer.release()
    kept.offer = nil
end

function Offer.update()
    local offer = Offer.standing()
    if offer ~= nil then offer:check() end
end

---@private
function Offer:check()
    local feed = Feed.find()
    if feed == nil or not feed:shortcut_is_ours() then
        note("notice", "offer %s gone: the game's shortcut replaced it", self.id)
        kept.offer = nil
        if self.lost then self.lost() end
    elseif os.clock() > self.until_at then
        feed:release_shortcut()
        kept.offer = nil
    end
end

function Offer:take()
    kept.offer = nil
    journal.later("notice", "offer %s taken", self.id)
    tasks.spawn("offer " .. self.id, function()
        Offer.release()
        self.action()
    end)
end

-- GUI020100.callbackOther: Y on our offer runs its action instead of the
-- empty System.Action.
---@param args HookArgs
local function on_feed_button(args)
    if arg.int(args[3]) ~= SHORTCUT_SLOT then return end
    local offer, feed = Offer.standing(), Feed.wrap(arg.object(args[2]))
    if offer == nil or feed == nil or not feed:shortcut_is_ours() then return end
    offer:take()
    return sdk.PreHookResult.SKIP_ORIGINAL
end

function Offer.install()
    hooks.on("app.GUI020100", "callbackOther(ace.GUIDef.BUTTON_SLOT, via.gui.Control, via.gui.SelectItem, System.UInt32)", on_feed_button)
end

return Offer
