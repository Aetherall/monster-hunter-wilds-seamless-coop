-- The quest the host invited us to: it is how that quest is joined, the
-- first time and again. It lasts as long as we are in the host's world
-- and, once we joined the quest, as long as the host is in it.

local FOLLOW_SECONDS, FOLLOW_DELAY = 30, 1

---@class sq.Invitation
---@field mission integer
---@field quest sq.AskedQuest       the quest the invite asks for
---@field private at number                 when the host invited
---@field private joined boolean            we joined it, at least once
---@field private playing_since number?     since when the host is seen playing it
local Invitation = {}
Invitation.__index = Invitation

---@param quest sq.AskedQuest
---@param at number
---@return sq.Invitation
function Invitation.new(quest, at)
    ---@type sq.Invitation
    local self = setmetatable({}, Invitation)
    self.mission, self.quest, self.at, self.joined = quest.mission, quest, at, false
    return self
end

function Invitation:mark_joined() self.joined = true end

---@return boolean
function Invitation:was_joined() return self.joined end

---@param at number
---@return boolean
function Invitation:expired(at) return at - self.at > FOLLOW_SECONDS end

---@param at number
---@return boolean
function Invitation:played_for_a_moment(at)
    return self.playing_since ~= nil and at - self.playing_since >= FOLLOW_DELAY
end

---@private
---@param host sq.Host
---@param at number
function Invitation:watch(host, at)
    if not host:playing() then
        self.playing_since = nil
        return
    end
    self.playing_since = self.playing_since or at
end

-- Once we joined the quest, it is over when the host is out of it.
---@private
---@param host sq.Host
---@return boolean
function Invitation:over(host) return self.joined and host:idle() end

---@param place sq.Place
---@param at number
---@return sq.Invitation?
function Invitation:continued(place, at)
    if not place:theirs() then return nil end
    local host = place:host()
    if host == nil then return self end
    if self:over(host) then return nil end
    self:watch(host, at)
    return self
end

return Invitation
