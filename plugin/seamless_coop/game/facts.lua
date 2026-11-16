-- The facts the world is derived from (world.lua), read off the game once
-- per frame: the only place that reads who is where. The lists are read
-- twice a second.

local memory = require("seamless_coop.base.memory")
local managers = require("seamless_coop.game.managers")
local Environment = require("seamless_coop.game.environment")
local Session = require("seamless_coop.game.session")
local LinkParty = require("seamless_coop.game.link_party")
local Quest = require("seamless_coop.game.quest")
local Scene = require("seamless_coop.game.scene")
local Missions = require("seamless_coop.game.missions")
local SessionType = Session.Type

local LIST_SECONDS = 0.5

---@class sq.PartyMember
---@field id string
---@field name string?
---@field stage integer
---@field questing boolean
---@field self boolean

---@class sq.Lists
---@field at number
---@field playable boolean
---@field loading boolean
---@field party_size integer
---@field session_ids table<string, boolean>   who is in our session
---@field party sq.PartyMember[]
---@field invites sq.Invite[]
---@field host sq.HostFacts?                   the session's host, in a link

---@class sq.HostFacts
---@field name string?
---@field id string?

-- What only exists in an Environment Link, which to the game is any quest
-- session with link sync: ours made to invite counts, with nobody in it.
---@class sq.LinkFacts
---@field hosting boolean
---@field session_size integer
---@field host_status sq.JoinStatus?

---@class sq.QuestRef
---@field key integer
---@field mission integer

---@class sq.Facts
---@field at number
---@field stage integer          during a load: -1
---@field questing boolean       MissionManager.IsActiveQuest
---@field link sq.LinkFacts?
---@field quest sq.QuestRef?
---@field lists sq.Lists

local Facts = {}

---@class sq.Facts.Kept
---@field last sq.Facts?
---@type sq.Facts.Kept
local kept = memory.keep("facts", {})

---@return table<string, boolean>
local function session_ids()
    local ids = {}
    for user in Session.users(SessionType.QUEST) do ids[user:id()] = true end
    return ids
end

---@return sq.PartyMember[]
local function party()
    ---@type sq.PartyMember[]
    local members = {}
    for user in Session.users(SessionType.LINK) do
        members[#members + 1] = { id = user:id(), name = user:name(), stage = user:stage(), questing = user:questing(),
            self = user:is_self() }
    end
    return members
end

---@return sq.Invite[]
local function invites()
    ---@type sq.Invite[]
    local list = {}
    for invite in LinkParty.invites() do list[#list + 1] = invite end
    return list
end

---@param linked boolean
---@return sq.HostFacts?
local function host_facts(linked)
    local host = linked and Session.host() or nil
    if host == nil then return nil end
    return { name = host:name(), id = host:known_id() }
end

---@param at number
---@param linked boolean
---@return sq.Lists
local function read_lists(at, linked)
    ---@type sq.Lists
    local lists = { at = at, playable = Scene.playable(), loading = Scene.loading(),
        party_size = Session.size(SessionType.LINK), session_ids = session_ids(), party = party(), invites = invites(),
        host = host_facts(linked) }
    return lists
end

---@return sq.LinkFacts?
local function read_link()
    if not Session.linked() then return nil end
    ---@type sq.LinkFacts
    local link = { hosting = Session.hosting(), session_size = Session.size(SessionType.QUEST), host_status = Session.host_status() }
    return link
end

-- The same quest keeps its value from one frame to the next.
---@param known sq.QuestRef?
---@return sq.QuestRef?
local function read_quest(known)
    local quest = Quest.current()
    if quest == nil then return nil end
    local key = quest:key()
    if known ~= nil and known.key == key then return known end
    return { key = key, mission = quest:mission() }
end

-- The frame's facts; nil until the game's managers exist.
---@return sq.Facts?
function Facts.read()
    local previous = kept.last
    if not managers.exist("app.EnvironmentManager", "app.MissionManager", "app.NetworkManager") then return nil end
    local at, link = os.clock(), read_link()
    ---@type sq.Lists
    local lists
    if previous ~= nil and at - previous.lists.at < LIST_SECONDS then
        lists = previous.lists
    else
        lists = read_lists(at, link ~= nil)
    end
    ---@type sq.Facts
    local facts = { at = at, stage = Environment.stage(), questing = Missions.questing(),
        link = link, quest = read_quest(previous and previous.quest), lists = lists }
    kept.last = facts
    return facts
end

return Facts
