-- The feed's one Y slot brought to what the policy wants on it.

local journal = require("seamless_coop.base.journal")
local memory = require("seamless_coop.base.memory")
local policy = require("seamless_coop.policy")
local World = require("seamless_coop.world")
local State = require("seamless_coop.state")
local Offer = require("seamless_coop.offer")
local RejoinOffer = require("seamless_coop.rejoin_offer")
local InviteOffer = require("seamless_coop.invite_offer")
local PartyQuestOffer = require("seamless_coop.party_quest_offer")
local note = journal.note

local OFFER_SECONDS = 60
local EVERY_SECONDS = 0.25

---@class sq.Offers
local Offers = {}

---@class sq.Offers.Kept
---@field known table<string, sq.Wanted>
---@field at number
---@type sq.Offers.Kept
local kept = memory.keep("offers", { known = {}, at = 0 })

---@param host sq.Host
---@param invited sq.Invitation
---@param outside sq.Outside
---@return sq.RejoinOffer
local function rejoin(host, invited, outside)
    local offer = kept.known[RejoinOffer.key()]
    if offer == nil then
        offer = RejoinOffer.of(host, invited, outside)
        kept.known[offer.id] = offer
    end
    ---@cast offer sq.RejoinOffer
    offer:update(host, invited, outside)
    return offer
end

---@param invite sq.Invite
---@return sq.InviteOffer
local function follow(invite)
    local offer = kept.known[InviteOffer.key(invite)]
    if offer == nil then
        offer = InviteOffer.of(invite)
        kept.known[offer.id] = offer
    end
    ---@cast offer sq.InviteOffer
    offer:update(invite)
    return offer
end

---@param quest sq.PartyQuest
---@param free sq.Free
---@return sq.PartyQuestOffer
local function party_quest(quest, free)
    local offer = kept.known[PartyQuestOffer.key(quest)]
    if offer == nil then
        offer = PartyQuestOffer.of(quest, free)
        kept.known[offer.id] = offer
    end
    ---@cast offer sq.PartyQuestOffer
    offer:update(quest, free)
    return offer
end

---@param w sq.World
---@param now sq.Now
---@return sq.Wanted[]
local function wanted_offers(w, now)
    ---@type sq.Wanted[]
    local list = {}
    policy.offers(w, now, {
        rejoin = function(host, invited, outside) list[#list + 1] = rejoin(host, invited, outside) end,
        party_quest = function(quest, free) list[#list + 1] = party_quest(quest, free) end,
        follow = function(invite) list[#list + 1] = follow(invite) end,
    })
    return list
end

---@param list sq.Wanted[]
---@param w sq.World
---@return sq.OfferPresence
local function presence_of(list, w)
    ---@type sq.OfferPresence
    local presence = { wanted = {}, invites = {} }
    for _, offer in ipairs(list) do presence.wanted[offer.id] = true end
    for _, invite in ipairs(w.invites) do presence.invites[invite.key] = true end
    return presence
end

-- Y comes some time after the offer was made: it is taken only if the
-- policy still names it.
---@async
---@param offer sq.Wanted
local function take(offer)
    local w = World.now()
    if w ~= nil then
        for _, current in ipairs(wanted_offers(w, State.now())) do
            if current.id == offer.id then return current:act() end
        end
    end
    note("notice", "offer %s taken: it no longer holds", offer.id)
end

-- False when the feed is not on screen: tried again later.
---@param offer sq.Wanted
---@param stage integer
---@return boolean
local function show(offer, stage)
    local text, prompt = offer:words(stage)
    local ok = Offer.make(offer.id, text, prompt, OFFER_SECONDS, function() take(offer) end,
        function() offer:taken_back() end)
    if ok then
        offer:made()
        note("notice", "offer %s made: %s", offer.id, text)
    end
    return ok
end

---@return boolean
local function due()
    if kept.at + EVERY_SECONDS > os.clock() then return false end
    kept.at = os.clock()
    return true
end

---@param presence sq.OfferPresence
local function forget_over(presence)
    for id, offer in pairs(kept.known) do
        if offer:over(presence) then kept.known[id] = nil end
    end
end

---@param presence sq.OfferPresence
---@return boolean
local function slot_free(presence)
    local standing = Offer.standing()
    if standing == nil then return true end
    if presence.wanted[standing.id] then return false end
    note("notice", "offer %s withdrawn: it no longer holds", standing.id)
    standing:withdraw()
    return true
end

---@param list sq.Wanted[]
---@return sq.Wanted?
local function next_due(list)
    for _, offer in ipairs(list) do
        if offer:due() then return offer end
    end
    return nil
end

---@param list sq.Wanted[]
---@param stage integer
local function show_next(list, stage)
    local offer = next_due(list)
    if offer ~= nil then show(offer, stage) end
end

---@param w sq.World
---@param now sq.Now
function Offers.reconcile(w, now)
    if not due() then return end
    local list = wanted_offers(w, now)
    local presence = presence_of(list, w)
    forget_over(presence)
    if slot_free(presence) then show_next(list, w.stage) end
end

-- The offers that stand are made again at once: the player just asked
-- for what one of them answers.
function Offers.remind()
    for _, offer in pairs(kept.known) do offer:again() end
end

return Offers
