-- A quest started or joined in place, inside the link's own session: what
-- the host's quest (ops/hosted_quest.lua) and a guest's
-- (ops/joined_quest.lua) have in common. In turn:
--
--   departing   the load's steps for the start, in place
--   playing     the quest is played. Its end becomes ours to make (an
--               OwnEnd) when it is armed; otherwise the ending is the
--               game's.
--   ending      the quest is over: the session left or kept, then the
--               field we came from

local journal = require("seamless_coop.base.journal")
local State = require("seamless_coop.state")
local Once = require("seamless_coop.base.once")
local Load = require("seamless_coop.ops.load")
local OwnEnd = require("seamless_coop.ops.own_end")
local Ending = require("seamless_coop.ops.ending")
local Session = require("seamless_coop.game.session")
local Quest = require("seamless_coop.game.quest")
local Director = require("seamless_coop.game.director")
local Environment = require("seamless_coop.game.environment")
local note = journal.note

-- The quest's start has populated the field this long after it.
local SETTLE_SECONDS = 5

---@class sq.QuestDeparting
---@field kind "departing"

---@class sq.QuestPlaying
---@field kind "playing"

---@class sq.QuestArmed
---@field kind "armed"
---@field ending sq.OwnEnd

---@class sq.QuestEnding
---@field kind "ending"
---@field ending sq.OwnEnd

---@alias sq.QuestPhase sq.QuestDeparting|sq.QuestPlaying|sq.QuestArmed|sq.QuestEnding
---@alias sq.SessionEnd "game"|"kept"|"left"

---@class sq.InQuest: sq.State
---@field protected load sq.Load
---@field protected departed_at number
---@field private phase sq.QuestPhase
---@field private key integer            the state is this quest's
local InQuest = setmetatable({}, { __index = State })
InQuest.__index = InQuest

---@protected
---@param quest sq.Quest
function InQuest:begin(quest)
    self.key, self.phase, self.departed_at = quest:key(), { kind = "departing" }, os.clock()
    self.load = Load.into(self)
end

-- The state belongs to its quest: on another quest (one joined by the
-- game's own accept, say) its cuts would be wrong (a stuck abandon,
-- 2026-11-15 19:25).
---@param world sq.World
---@return boolean holds, string? why
function InQuest:holds(world)
    if (self.phase.kind == "playing" or self.phase.kind == "armed") and world.quest ~= nil and world.quest.key ~= self.key then
        return false, "we are in another quest"
    end
    return true
end

---@return string
function InQuest:describe()
    ---@type string
    local phase = self.phase.kind
    if phase == "armed" then phase = "playing, armed" end
    if phase == "ending" then phase = "ending, armed" end
    return string.format("%s (%s)", self.kind, phase)
end

---@protected
---@return async fun(): boolean?
function InQuest:played()
    self.phase = { kind = "playing" }
    local first = true
    ---@async
    return function()
        if not first then self:frame() end
        first = false
        if Quest.current() == nil then return nil end
        return true
    end
end

-- When the quest's end is armed, given when its field is settled. For
-- each class to define.
---@protected
---@param _settled_at number
---@return number
function InQuest:arm_time(_settled_at) error("arm_time: for each class to define") end

-- The quest's start is done populating the field. For each class to
-- define.
---@protected
function InQuest:settled() error("settled: for each class to define") end

---@protected
function InQuest:while_played() end

---@protected
---@async
function InQuest:play()
    local settled_at = os.clock() + SETTLE_SECONDS
    local settle, arm = Once.at(settled_at), Once.at(self:arm_time(settled_at))
    for _ in self:played() do
        if settle:due() then self:settled() end
        if arm:due() then self:arm() end
        self:shape_end()
        self:while_played()
    end
end

-- The quest's end becomes ours to make in place when its return load
-- would bring us back to the stage we are in.
---@protected
function InQuest:arm()
    if not Session.multiplay() then
        note("leave", "quest end left to the game: not in a quest session")
        return
    end
    local here, back = Environment.stage(), Director.return_stage()
    if here ~= back then
        note("leave", "quest end left to the game: the quest returns to stage %s, we are in %s", back, here)
        return
    end
    self.phase = { kind = "armed", ending = OwnEnd.new() }
    note("leave", "this quest ends without the return load")
end

---@protected
---@return boolean
function InQuest:armed() return self.phase.kind == "armed" end

---@protected
function InQuest:shape_end()
    local phase = self.phase
    if phase.kind ~= "armed" then return end
    ---@cast phase sq.QuestArmed
    Ending.shape(phase.ending)
end

-- The quest is over. When its end is ours and the game asked for its
-- return jump: the session left or kept, or the end was the game's.
---@protected
---@async
---@return sq.SessionEnd
function InQuest:end_session()
    local phase = self.phase
    if phase.kind ~= "armed" then return "game" end
    ---@cast phase sq.QuestArmed
    local ending = phase.ending
    if ending:jumps_cut() == 0 then self:stop("the quest ended and the game asked for no jump") end
    note("leave", "quest ended, its return jump answered false %d times", ending:jumps_cut())
    self.phase = { kind = "ending", ending = ending }
    self:frame()
    if Load.out(self):session_left(false) then return "kept" end
    return "left"
end

-- The game asks whether the quest that ended jumps back: not when its end
-- is ours. As a field quest's is, and the game runs that ending.
---@return boolean cut
function InQuest:cut_return_jump()
    local ending = self:ending()
    if ending == nil then return false end
    ending:count_jump()
    return true
end

-- The end that is ours, while its quest is played.
---@return sq.OwnEnd?
function InQuest:shaped_end()
    local phase = self.phase
    if phase.kind == "armed" then return phase.ending end
    return nil
end

-- The end that is ours, at any time.
---@return sq.OwnEnd?
function InQuest:ending()
    local phase = self.phase
    if phase.kind == "armed" or phase.kind == "ending" then return phase.ending end
    return nil
end

return InQuest
