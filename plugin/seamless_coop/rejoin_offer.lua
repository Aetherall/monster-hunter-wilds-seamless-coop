local Words = require("seamless_coop.words")
local QuestStart = require("seamless_coop.ops.quest_start")

local AGAIN_SECONDS = 60

---@class sq.RejoinOffer: sq.Wanted
---@field private host sq.Host
---@field private invited sq.Invitation
---@field private outside sq.Outside     the state we wait in, which the join starts from
---@field private at number?
local RejoinOffer = {}
RejoinOffer.__index = RejoinOffer

---@param host sq.Host
---@param invited sq.Invitation
---@param outside sq.Outside
---@return sq.RejoinOffer
function RejoinOffer.of(host, invited, outside)
    ---@type sq.RejoinOffer
    local self = setmetatable({}, RejoinOffer)
    self.id, self.host, self.invited, self.outside = RejoinOffer.key(), host, invited, outside
    return self
end

---@return string
function RejoinOffer.key() return "rejoin" end

---@param host sq.Host
---@param invited sq.Invitation
---@param outside sq.Outside
function RejoinOffer:update(host, invited, outside) self.host, self.invited, self.outside = host, invited, outside end

---@return string, string
function RejoinOffer:words() return Words.rejoin(self.host) end

---@async
function RejoinOffer:act()
    QuestStart.join(self.invited, "Y on the offer", self.outside)
end

---@return boolean
function RejoinOffer:due() return self.at == nil or os.clock() >= self.at + AGAIN_SECONDS end

function RejoinOffer:made() self.at = os.clock() end

-- A taken-back rejoin offer still waits for its interval.
function RejoinOffer:taken_back() end

function RejoinOffer:again() self.at = nil end

---@param presence sq.OfferPresence
---@return boolean
function RejoinOffer:over(presence) return not presence.wanted[self.id] end

return RejoinOffer
