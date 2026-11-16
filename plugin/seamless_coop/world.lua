-- The situation we are in, derived once per frame from the facts read off
-- the game (game/facts.lua). Every decision (policy.lua) reads this and
-- what the plugin is doing (state.lua), nothing else. No game calls.
--
-- Each part is one of a few named cases, and what only exists in a case
-- lives inside it: there is no host to ask about outside "guest", no
-- quest to read when none is on the director, no host's invitation
-- outside a host's world.
--
--   place    whose world we stand in (place.lua)
--   members  the link party's other members, each { name, stage, relation }
--     "together"  in our session: the same world
--     "near"      in our stage, in another world
--     "apart"     in another stage
--   quest    nil, or the quest on our director { key, mission }
--   questing the game's own "a quest is active"
--   link     nil, or who we were in the last link { as = "host" | "guest",
--            questing, left_at }: a guest's leave reaches its hooks once
--            the session is left (left_at is nil while the link lasts)
--   settled  false for a few seconds after a travel or a return to our own
--            world, while the other members' stage, as we see it, is stale
--   invitation  nil, or the quest the host invited us to (invitation.lua)
--   heard    the quests of other members we were told of and are not in
--            (party_quest.lua), one per member
--
-- The frame's work is handed the frame's world. A hook or a task, which
-- runs at another time, asks for the latest one: World.now().

local memory = require("seamless_coop.base.memory")
local Place = require("seamless_coop.place")
local Invitation = require("seamless_coop.invitation")

local QUIET_SECONDS = 10
-- A guest's leave is seen by the game's hooks this long after the link.
local LEFT_SECONDS = 5

---@alias sq.Role "host"|"guest"
---@alias sq.Relation "together"|"near"|"apart"

---@class sq.Member
---@field id string
---@field name string?
---@field stage integer
---@field questing boolean
---@field relation sq.Relation

---@class sq.Link
---@field as sq.Role
---@field questing boolean
---@field left_at number?    nil while the link lasts

---@class sq.Travel
---@field from integer
---@field to integer

-- What a frame's world hands to the next one.
---@class sq.Legacy
---@field known_stage integer?
---@field quiet_until number
---@field link sq.Link?
---@field invited sq.Invitation?
---@field alone boolean
---@field heard table<string, sq.PartyQuest>

---@type sq.Legacy
local NOTHING = { quiet_until = 0, alone = true, heard = {} }

---@class sq.World
---@field at number
---@field enabled boolean
---@field stage integer            during a load: -1
---@field known_stage integer?     the last stage that was not a load's
---@field travelled sq.Travel?     this frame
---@field playable boolean
---@field loading boolean
---@field place sq.Place
---@field quest sq.QuestRef?
---@field questing boolean
---@field link sq.Link?
---@field party_size integer
---@field invites sq.Invite[]
---@field settled boolean
---@field private others sq.Member[]
---@field private quiet_until number
---@field private invited sq.Invitation?
---@field private heard table<string, sq.PartyQuest>   by member id
local World = {}
World.__index = World

---@param member sq.PartyMember
---@param lists sq.Lists
---@param our_stage integer
---@return sq.Relation
local function relation_of(member, lists, our_stage)
    if lists.session_ids[member.id] then return "together" end
    if member.stage == our_stage then return "near" end
    return "apart"
end

---@param facts sq.Facts
---@return sq.Member[]
local function members_of(facts)
    ---@type sq.Member[]
    local members = {}
    for _, member in ipairs(facts.lists.party) do
        if not member.self then
            members[#members + 1] = { id = member.id, name = member.name, stage = member.stage, questing = member.questing,
                relation = relation_of(member, facts.lists, facts.stage) }
        end
    end
    return members
end

-- The stage is -1 during a load: the last one known is kept.
---@param known integer?
---@param stage integer
---@return integer? known, sq.Travel? travelled
local function stage_memory(known, stage)
    if stage < 0 then return known, nil end
    if known ~= nil and known ~= stage then return stage, { from = known, to = stage } end
    return stage, nil
end

---@param link sq.LinkFacts
---@return sq.Role
local function role_in(link)
    if link.hosting then return "host" end
    return "guest"
end

-- A guest's leave reaches its hooks once the session is left: who we were
-- in the link is kept after it.
---@param facts sq.Facts
---@param previous sq.Link?
---@return sq.Link?
local function link_memory(facts, previous)
    if facts.link ~= nil then return { as = role_in(facts.link), questing = facts.questing } end
    if previous == nil then return nil end
    return { as = previous.as, questing = previous.questing, left_at = previous.left_at or facts.at }
end

-- The other members' stage, as we see it, is stale for a moment after a
-- travel or a return to our own world.
---@param before sq.Legacy
---@param place sq.Place
---@param travelled sq.Travel?
---@param at number
---@return number
local function quiet_until(before, place, travelled, at)
    local came_home = not before.alone and place:alone()
    if travelled ~= nil or came_home then return at + QUIET_SECONDS end
    return before.quiet_until
end

---@param invited sq.Invitation?
---@param place sq.Place
---@param at number
---@return sq.Invitation?
local function continued(invited, place, at)
    if invited == nil then return nil end
    return invited:continued(place, at)
end

-- The quests we were told of, one frame later: each lasts as long as its
-- member is in the party and in it.
---@param heard table<string, sq.PartyQuest>
---@param members sq.Member[]
---@param at number
---@return table<string, sq.PartyQuest>
local function still_heard(heard, members, at)
    ---@type table<string, sq.PartyQuest>
    local still = {}
    for _, member in ipairs(members) do
        local quest = heard[member.id]
        if quest ~= nil then still[member.id] = quest:continued(member.questing, at) end
    end
    return still
end

---@class sq.World.Kept
---@field now sq.World?
---@type sq.World.Kept
local kept = memory.keep("world", {})

-- The latest world, nil before the first frame: for hooks and tasks.
---@return sq.World?
function World.now() return kept.now end

---@param facts sq.Facts
---@param enabled boolean
---@return sq.World
function World.observe(facts, enabled)
    local before = NOTHING
    if kept.now ~= nil then before = kept.now:legacy() end
    kept.now = World.derive(facts, before, enabled)
    return kept.now
end

---@private
---@return sq.Legacy
function World:legacy()
    return { known_stage = self.known_stage, quiet_until = self.quiet_until, link = self.link, invited = self.invited,
        alone = self.place:alone(), heard = self.heard }
end

---@private
---@param facts sq.Facts
---@param before sq.Legacy
---@param enabled boolean
---@return sq.World
function World.derive(facts, before, enabled)
    local lists, at = facts.lists, facts.at
    ---@type sq.World
    local self = setmetatable({}, World)
    self.at, self.enabled = at, enabled
    self.place, self.others = Place.of(facts.link, lists.host), members_of(facts)
    self.stage = facts.stage
    self.known_stage, self.travelled = stage_memory(before.known_stage, facts.stage)
    self.playable, self.loading = lists.playable, lists.loading
    self.quest, self.questing = facts.quest, facts.questing
    self.link = link_memory(facts, before.link)
    self.party_size, self.invites = lists.party_size, lists.invites
    self.quiet_until = quiet_until(before, self.place, self.travelled, at)
    self.settled = at >= self.quiet_until
    self.invited = continued(before.invited, self.place, at)
    self.heard = still_heard(before.heard, self.others, at)
    return self
end

---@param stage integer?
---@return boolean
function World:other_stage(stage) return stage ~= self.stage end

---@return boolean
function World:alone() return self.place:alone() end

-- In a session of ours, alone in it or not.
---@return boolean
function World:hosting() return self.place:ours() end

---@return boolean
function World:solo() return self.place:is("solo") end

---@return sq.Invitation?
function World:invitation() return self.invited end

-- The host invites to a quest. False in a place that has no host.
---@param quest sq.AskedQuest
---@return boolean
function World:invite(quest)
    if not self.place:is("guest") then return false end
    self.invited = Invitation.new(quest, os.clock())
    return true
end

function World:forget_invitation() self.invited = nil end

---@return boolean
function World:host_playing()
    local host = self.place:host()
    return host ~= nil and host:playing()
end

---@return boolean
function World:host_in_quest()
    local host = self.place:host()
    return host ~= nil and host:in_quest()
end

-- A member announces a quest of theirs: it replaces the one we knew of
-- them.
---@param quest sq.PartyQuest
function World:hear(quest) self.heard[quest.by] = quest end

---@param member_id string?
---@return sq.PartyQuest?
function World:quest_of(member_id) return self.heard[member_id] end

---@param stage integer
---@return sq.PartyQuest?
function World:quest_in(stage)
    for _, quest in pairs(self.heard) do
        if quest.stage == stage then return quest end
    end
    return nil
end

---@private
---@param member sq.Member
---@return sq.PartyQuest?
function World:heard_elsewhere(member)
    if member.relation == "together" then return nil end
    return self.heard[member.id]
end

---@return fun(): sq.PartyQuest?
function World:quests_elsewhere()
    local i = 0
    return function()
        repeat
            i = i + 1
            local member = self.others[i]
            if member == nil then return nil end
            local quest = self:heard_elsewhere(member)
            if quest ~= nil then return quest end
        until false
    end
end

---@return boolean
function World:in_party() return self.party_size >= 2 end

---@param relation sq.Relation?
---@return fun(): sq.Member?
function World:members(relation)
    local i = 0
    return function()
        repeat
            i = i + 1
            local member = self.others[i]
            if member == nil or relation == nil or member.relation == relation then return member end
        until false
    end
end

-- A guest that left a link a moment ago, or is leaving it: the game's
-- hooks see the leave once the session is already left.
---@return boolean
function World:guest_leaving()
    local link = self.link
    if link == nil or link.as ~= "guest" or link.questing then return false end
    return link.left_at == nil or self.at - link.left_at < LEFT_SECONDS
end

-- The invites that stand for where their inviter is: each inviter's
-- latest.
---@return fun(): sq.Invite?
function World:standing_invites()
    ---@type table<string, integer>
    local latest = {}
    for _, invite in ipairs(self.invites) do latest[invite.from] = invite.key end
    local i = 0
    return function()
        repeat
            i = i + 1
            local invite = self.invites[i]
            if invite == nil or latest[invite.from] == invite.key then return invite end
        until false
    end
end

---@return string
function World:describe()
    local parts = { string.format("stage %s", self.stage), self.place.kind }
    local host = self.place:host()
    if host ~= nil then parts[#parts + 1] = string.format("of %s (%s)", host.name, host.quest) end
    if self.questing then parts[#parts + 1] = "in a quest" end
    for member in self:members() do parts[#parts + 1] = string.format("%s %s", member.name, member.relation) end
    return table.concat(parts, ", ")
end

return World
