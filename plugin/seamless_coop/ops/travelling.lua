-- On our way to the stage of a quest: the travel, when we are not there
-- yet, then what we came for (`arrived`, which the one who starts the
-- travel brings: ops/quest_travel.lua). While it lasts nothing else of
-- ours starts: a link we leave by travelling is left by the game.
--
-- The rule: a quest is played where it is; whoever
-- wants in travels there on their own, each at the same time, and is
-- then joined in place. Everyone stays in the quest's stage afterwards.
--
-- UNVERIFIED, all of it but the travel alone and in no link
-- (game/travel.lua): this state has never run.

local journal = require("seamless_coop.base.journal")
local State = require("seamless_coop.state")
local World = require("seamless_coop.world")
local Travel = require("seamless_coop.game.travel")
local Feed = require("seamless_coop.game.feed")
local note = journal.note

-- The hunter is given a moment after the counter or the offer before it
-- is asked to depart.
local DEPART_SECONDS = 0.5
-- Alone and in no link a travel took 15 s; in a link it is a load.
local ARRIVAL_SECONDS = 90

---@class sq.Travelling: sq.State
---@field stage integer    where we go
---@field private arrived async fun(state: sq.Travelling)
local Travelling = setmetatable({}, { __index = State })
Travelling.__index = Travelling

---@param from sq.Free
---@param stage integer
---@param arrived async fun(state: sq.Travelling)   what we came for, inside the state's task
---@return boolean entered
function Travelling.from(from, stage, arrived)
    ---@type sq.Travelling
    local self = setmetatable({}, Travelling)
    self.kind, self.stage, self.arrived = "travelling", stage, arrived
    return self:enter(from)
end

---@param stage integer
---@return boolean
local function there(stage)
    local w = World.now()
    if w == nil or w.stage ~= stage then return false end
    return w.playable and not w.loading and not Travel.under_way()
end

---@param why string   the journal's
---@return never
function Travelling:give_up(why)
    Feed.say("Could not get to the quest")
    return self:stop(why)
end

---@private
---@async
function Travelling:travel()
    local stage = self.stage
    if there(stage) then return end
    if not Travel.to(stage) then self:give_up(string.format("no travel to stage %s", stage)) end
    note("travel", "travel to stage %s asked", stage)
    if not self:wait_until(ARRIVAL_SECONDS, function() return there(stage) end) then
        self:give_up(string.format("not in stage %s after %d s", stage, ARRIVAL_SECONDS))
    end
    note("travel", "arrived in stage %s", stage)
end

---@async
function Travelling:run()
    self:sleep(DEPART_SECONDS)
    self:travel()
    self.arrived(self)
end

return Travelling
