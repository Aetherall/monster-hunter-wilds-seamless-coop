local Words = require("seamless_coop.words")
local Party = require("seamless_coop.ops.party")

local RETRIES = 3

---@class sq.InviteOffer: sq.Wanted
---@field private invite sq.Invite
---@field private lost integer
---@field private retry boolean
---@field private shown boolean
local InviteOffer = {}
InviteOffer.__index = InviteOffer

---@param invite sq.Invite
---@return sq.InviteOffer
function InviteOffer.of(invite)
    ---@type sq.InviteOffer
    local self = setmetatable({}, InviteOffer)
    self.id, self.invite = InviteOffer.key(invite), invite
    self.lost, self.retry, self.shown = 0, false, false
    return self
end

---@param invite sq.Invite
---@return string
function InviteOffer.key(invite) return "follow:" .. tostring(invite.key) end

---@param invite sq.Invite
function InviteOffer:update(invite) self.invite = invite end

---@param stage integer
---@return string, string
function InviteOffer:words(stage) return Words.invite(self.invite, stage) end

---@async
function InviteOffer:act() Party.accept(self.invite) end

---@return boolean
function InviteOffer:due() return not self.shown or self.retry end

function InviteOffer:made() self.shown, self.retry = true, false end

function InviteOffer:taken_back()
    self.lost = self.lost + 1
    self.retry = self.lost <= RETRIES
end

function InviteOffer:again() self.retry = true end

---@param presence sq.OfferPresence
---@return boolean
function InviteOffer:over(presence) return not presence.invites[self.invite.key] end

return InviteOffer
