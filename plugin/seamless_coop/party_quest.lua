-- A quest of another member of the link party, which we are not in: it
-- was announced to us by its quest invite. One per member. It is how
-- that quest is offered ("A quest is going on in ...") and, once we
-- stand in its host's world, how it is joined.
--
-- It lasts from its announcement until its member is out of the quest.
-- UNVERIFIED: "in a quest" is read off the link party's member list
-- (game/user.lua, IsQuest). If that flag does not reach us across
-- sessions, the quest is forgotten ANNOUNCED_SECONDS after its
-- announcement and can no longer be joined from the offer.

-- How long an announced quest may take to start: its member travels to
-- its stage first.
local ANNOUNCED_SECONDS = 120

---@class sq.PartyQuest
---@field by string                 its member's hunter id
---@field name string?              its member's name
---@field asked sq.AskedQuest
---@field stage integer             the stage it is played in
---@field private at number                 when it was announced
---@field private seen_played boolean       its member was seen in a quest since
local PartyQuest = {}
PartyQuest.__index = PartyQuest

---@param by string
---@param name string?
---@param asked sq.AskedQuest
---@param at number
---@return sq.PartyQuest
function PartyQuest.new(by, name, asked, at)
    ---@type sq.PartyQuest
    local self = setmetatable({}, PartyQuest)
    self.by, self.name, self.asked, self.stage = by, name, asked, asked:stage()
    self.at, self.seen_played = at, false
    return self
end

-- The quest one frame later; nil once it is over, or was never started.
---@param member_questing boolean
---@param at number
---@return sq.PartyQuest?
function PartyQuest:continued(member_questing, at)
    if member_questing then
        self.seen_played = true
        return self
    end
    if self.seen_played or at - self.at > ANNOUNCED_SECONDS then return nil end
    return self
end

return PartyQuest
