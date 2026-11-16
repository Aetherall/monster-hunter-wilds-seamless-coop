-- The quest a quest invite asks for, or a post at our own counter. A
-- quest of the game's table is known by its mission alone and built when
-- it is started; an investigation is not in the table and travels in the
-- invite, from which it is rebuilt as the invite is received.

local journal = require("seamless_coop.base.journal")
local Quest = require("seamless_coop.game.quest")
local note = journal.note

---@class sq.AskedQuest
---@field mission integer
---@field private rebuilt sq.Quest?   an investigation, rebuilt from the invite
local AskedQuest = {}
AskedQuest.__index = AskedQuest

---@private
---@param mission integer
---@param rebuilt sq.Quest?
---@return sq.AskedQuest
function AskedQuest.new(mission, rebuilt)
    ---@type sq.AskedQuest
    local self = setmetatable({}, AskedQuest)
    self.mission, self.rebuilt = mission, rebuilt
    return self
end

---@param mission integer
---@return sq.AskedQuest?
function AskedQuest.of(mission)
    if Quest.in_table(mission) then return AskedQuest.new(mission, nil) end
    local rebuilt = Quest.from_invite(mission)
    if rebuilt == nil then
        note("quest", "mission %d is not in the quest table and its invite carries no quest: left to the game", mission)
        return nil
    end
    note("quest", "mission %d is an investigation: quest rebuilt from the invite (%s)", mission, rebuilt:describe())
    return AskedQuest.new(mission, rebuilt)
end

-- The quest posted at our own counter, to be started without the counter
-- once we stand in its stage. Only a quest of the game's table: an
-- investigation's data is the counter's, and whether it outlives the
-- counter was not looked at.
---@param posted sq.Quest
---@return sq.AskedQuest?
function AskedQuest.posted(posted)
    local mission = posted:mission()
    if not Quest.in_table(mission) then return nil end
    return AskedQuest.new(mission, nil)
end

---@return integer
function AskedQuest:stage()
    if self.rebuilt ~= nil then return self.rebuilt:stage() end
    return Quest.table_stage(self.mission)
end

---@return sq.Quest
function AskedQuest:quest() return self.rebuilt or Quest.of_table(self.mission) end

return AskedQuest
