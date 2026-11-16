-- The host's quest, joined late and in place: the host's quest field is
-- taken, the quest is played, and then either our own field comes back
-- (the session was left) or we wait outside the quest, in the host's
-- world (the link goes on).

local journal = require("seamless_coop.base.journal")
local InQuest = require("seamless_coop.ops.in_quest")
local Outside = require("seamless_coop.ops.outside")
local HostWatch = require("seamless_coop.ops.host_watch")
local Load = require("seamless_coop.ops.load")
local Session = require("seamless_coop.game.session")
local Director = require("seamless_coop.game.director")
local Hunter = require("seamless_coop.game.hunter")
local note = journal.note

-- The end is armed this long after the departure.
local ARM_SECONDS = 3

---@class sq.JoinedQuest: sq.InQuest
---@field private host sq.HostWatch   the host, as seen from the quest
local JoinedQuest = setmetatable({}, { __index = InQuest })
JoinedQuest.__index = JoinedQuest

---@param from sq.Departing
---@param quest sq.Quest
---@return boolean entered
function JoinedQuest.from(from, quest)
    ---@type sq.JoinedQuest
    local self = setmetatable({}, JoinedQuest)
    self.kind, self.host = "joined", HostWatch.new()
    self:begin(quest)
    return self:enter(from)
end

---@private
---@async
function JoinedQuest:take_quest_field()
    local load = self.load
    load:settle()
    load:environment("quest")
    local deadline = load:notify(true)
    load:late_join(true, deadline)
    Load.fade_in()
end

-- When the host is seen out of the quest (abandoned) while ours is still
-- being played, ours is cancelled too; its field is the host's.
---@private
function JoinedQuest:follow_host_out()
    if not Session.linked() then return end
    local status = Session.host_status()
    if not self.host:out(status) or not Director.at("cQuestPlaying") then return end
    self.host:done()
    note("leave", "the host is out of the quest (status %s): ours cancelled", status)
    Director.cancel()
end

-- Still the host's guest: its field comes back by entering its world
-- again once the host has restored it, not from our save.
---@private
function JoinedQuest:wait_outside()
    note("leave", "quest ended, link session kept: waiting for the host")
    Director.finish_end()
    Hunter.release_retire_pose()
    Outside.from(self)
end

---@private
---@async
function JoinedQuest:bring_field_back()
    local load = Load.out(self)
    load:drop_host_schedule()
    load:restore_field(false)
    Director.finish_end()
    Load.settle_home()
end

---@protected
---@param _settled_at number
---@return number
function JoinedQuest:arm_time(_settled_at) return self.departed_at + ARM_SECONDS end

---@protected
function JoinedQuest:settled() Load.remove_duplicates("join") end

---@protected
function JoinedQuest:while_played()
    if self:armed() then self:follow_host_out() end
end

---@async
function JoinedQuest:run()
    self:take_quest_field()
    self:play()
    local outcome = self:end_session()
    if outcome == "game" then return end
    if outcome == "kept" then
        self:wait_outside()
    else
        self:bring_field_back()
    end
end

return JoinedQuest
