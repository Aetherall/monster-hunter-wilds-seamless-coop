local Words = require("seamless_coop.words")
local QuestTravel = require("seamless_coop.ops.quest_travel")

local AGAIN_SECONDS = 60

---@class sq.PartyQuestOffer: sq.Wanted
---@field private quest sq.PartyQuest
---@field private free sq.Free     the state the travel starts from
---@field private at number?
local PartyQuestOffer = {}
PartyQuestOffer.__index = PartyQuestOffer

---@param quest sq.PartyQuest
---@param free sq.Free
---@return sq.PartyQuestOffer
function PartyQuestOffer.of(quest, free)
    ---@type sq.PartyQuestOffer
    local self = setmetatable({}, PartyQuestOffer)
    self.id, self.quest, self.free = PartyQuestOffer.key(quest), quest, free
    return self
end

-- One offer per member.
---@param quest sq.PartyQuest
---@return string
function PartyQuestOffer.key(quest) return "quest:" .. quest.by end

---@param quest sq.PartyQuest
---@param free sq.Free
function PartyQuestOffer:update(quest, free) self.quest, self.free = quest, free end

---@param stage integer
---@return string, string
function PartyQuestOffer:words(stage) return Words.party_quest(self.quest, stage) end

---@async
function PartyQuestOffer:act() QuestTravel.join(self.quest, self.free) end

---@return boolean
function PartyQuestOffer:due() return self.at == nil or os.clock() >= self.at + AGAIN_SECONDS end

function PartyQuestOffer:made() self.at = os.clock() end

-- A taken-back offer still waits for its interval.
function PartyQuestOffer:taken_back() end

function PartyQuestOffer:again() self.at = nil end

---@param presence sq.OfferPresence
---@return boolean
function PartyQuestOffer:over(presence) return not presence.wanted[self.id] end

return PartyQuestOffer
