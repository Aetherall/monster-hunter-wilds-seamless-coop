-- Whose world we stand in.
--
--   solo      ours, no session
--   open      ours, in the session we made to invite the party (an
--             Environment Link to the game), nobody else in it
--   host      ours, with link members in it
--   joining   a session that is not ours and shows nobody else yet: on
--             our way into someone's world
--   guest     the session host's; only this place has a host

local User = require("seamless_coop.game.user")
local JoinStatus = User.JoinStatus

---@alias sq.HostQuestState "idle"|"playing"|"ending"|"unknown"
---@alias sq.PlaceKind "solo"|"open"|"host"|"joining"|"guest"

---@class sq.Host
---@field name string?
---@field id string?                the host's hunter id
---@field quest sq.HostQuestState   where the host is with a quest
local Host = {}
Host.__index = Host

---@param status sq.JoinStatus?
---@return sq.HostQuestState
local function host_quest(status)
    if status == nil then return "unknown" end
    if status < JoinStatus.START then return "idle" end
    if status == JoinStatus.START then return "playing" end
    return "ending"
end

---@param facts sq.HostFacts?
---@param status sq.JoinStatus?
---@return sq.Host
function Host.of(facts, status)
    ---@type sq.Host
    local self = setmetatable({}, Host)
    self.quest = host_quest(status)
    if facts ~= nil then self.name, self.id = facts.name, facts.id end
    return self
end

---@return boolean
function Host:playing() return self.quest == "playing" end

---@return boolean
function Host:idle() return self.quest == "idle" end

---@return boolean
function Host:in_quest() return self.quest == "playing" or self.quest == "ending" end

-- An answer for every place. Only a guest's has a host.
---@class sq.PlaceCases
---@field solo fun(): any
---@field open fun(): any
---@field host fun(): any
---@field joining fun(): any
---@field guest fun(host: sq.Host): any

---@class sq.Place
---@field kind sq.PlaceKind
---@field private guest_of sq.Host?
local Place = {}
Place.__index = Place
Place.Host = Host

---@type table<boolean, sq.PlaceKind>
local OURS = { [true] = "host", [false] = "open" }
---@type table<boolean, sq.PlaceKind>
local THEIRS = { [true] = "guest", [false] = "joining" }

---@param link sq.LinkFacts?
---@return sq.PlaceKind
local function kind_of(link)
    if link == nil then return "solo" end
    local kinds = link.hosting and OURS or THEIRS
    local with_others = link.session_size > 1
    return kinds[with_others]
end

---@param link sq.LinkFacts?
---@param host sq.HostFacts?
---@return sq.Place
function Place.of(link, host)
    ---@type sq.Place
    local self = setmetatable({}, Place)
    self.kind = kind_of(link)
    if link ~= nil and self.kind == "guest" then
        self.guest_of = Host.of(host, link.host_status)
    end
    return self
end

---@param kind sq.PlaceKind
---@return boolean
function Place:is(kind) return self.kind == kind end

---@param cases sq.PlaceCases
---@return any
function Place:match(cases)
    ---@type any
    local case = cases[self.kind]
    return case(self.guest_of)
end

---@return sq.Host?
function Place:host() return self.guest_of end

---@return boolean
function Place:alone() return self.kind ~= "host" and self.kind ~= "guest" end

-- A session of ours, which the game takes for an Environment Link.
---@return boolean
function Place:ours() return self.kind == "open" or self.kind == "host" end

-- Someone else's session, whether its host shows yet or not.
---@return boolean
function Place:theirs() return self.kind == "guest" or self.kind == "joining" end

return Place
