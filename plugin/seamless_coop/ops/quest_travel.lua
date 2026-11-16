-- The ways a quest in another stage, or in another member's world, is
-- reached: a travel on our own (ops/travelling.lua), then the start or
-- the join in place.
--
-- UNVERIFIED, every step: none of this has run. What each step assumes
-- of the game is said where it is made.

local journal = require("seamless_coop.base.journal")
local tasks = require("seamless_coop.base.tasks")
local World = require("seamless_coop.world")
local Travelling = require("seamless_coop.ops.travelling")
local Departing = require("seamless_coop.ops.departing")
local Party = require("seamless_coop.ops.party")
local LinkParty = require("seamless_coop.game.link_party")
local Director = require("seamless_coop.game.director")
local Feed = require("seamless_coop.game.feed")
local note = journal.note

local QuestTravel = {}

-- How long our session may take to show as ours once it is online.
local SESSION_SECONDS = 5
-- How long the quest's host may take to arrive and invite: it travels
-- too, and may have left after us.
local HOST_SECONDS = 120

-- The party is told of the quest before we leave, by the quest invite
-- the game sends for a quest (as a member's post asks its host,
-- QuestStart.ask_host): that is what lets everyone travel at the same
-- time. ASSUMED: the invite reaches every member of the link party, in
-- our session or not (seen across sessions on 2026-11-15 19:16), and
-- being sent before we host anything does no harm.
---@param posted sq.Quest
local function announce(posted)
    local ok, err = Director.lend(posted, LinkParty.invite_to_quest_as_member)
    if not ok then note("error", "mission %d not announced to the party: %s", posted:mission(), err) end
end

---@return boolean
local function hosting()
    local w = World.now()
    return w ~= nil and w:hosting()
end

-- Arrived: the party is invited to our world here, then the quest is
-- started without the counter, as the host starts a member's quest
-- (QuestStart.for_member). The invite is ours to send whatever the
-- frame's own invite after a travel does (frame.lua): a second one only
-- replaces the first. ASSUMED: a session of ours with nobody else in it
-- is enough for that start (a quest posted at the counter in such a
-- session started in place on 2026-11-15 19:16); the invite sent before
-- the start can still be accepted once we are in the quest.
---@async
---@param state sq.Travelling
---@param asked sq.AskedQuest
local function start_here(state, asked)
    if not Party.invite(state.stage) then state:give_up("no session of ours to start the quest in") end
    if not state:wait_until(SESSION_SECONDS, hosting) then state:give_up("our session does not show as ours") end
    Departing.from(state, "host", asked.mission, function() Director.start(asked) end)
end

-- A board quest posted for another stage: the party told, the counter
-- ended as after an accept (as for a member's post: both inside the
-- counter's own call), then the travel and the start there.
---@param counter sq.Counter
---@param posted sq.Quest
---@param asked sq.AskedQuest
---@param stage integer
---@param free sq.Free
---@return boolean started
function QuestTravel.post(counter, posted, asked, stage, free)
    if not Travelling.from(free, stage, function(state) start_here(state, asked) end) then return false end
    announce(posted)
    counter:finish()
    note("quest", "mission %d is in stage %s: the party told, travelling there to start it", asked.mission, stage)
    return true
end

-- The environment invite of `by` to `stage`, once it stands. ASSUMED: an
-- invite's inviter and a party member are told apart by the same hunter
-- id.
---@param by string
---@param stage integer
---@return sq.Invite?
local function invite_of(by, stage)
    local w = World.now()
    if w == nil then return nil end
    for invite in w:standing_invites() do
        if invite.from == by and invite.stage == stage then return invite end
    end
    return nil
end

-- Arrived where the quest is: its host's invite to its world is accepted
-- without asking again (Y on the offer was the answer). Its world is
-- then entered in place and its quest joined, by what does that for any
-- host we stand with (frame.lua). ASSUMED: a host in a quest still has
-- its invite accepted, and its world can be entered in place while its
-- quest runs.
---@async
---@param state sq.Travelling
---@param quest sq.PartyQuest
local function enter_world(state, quest)
    ---@type sq.Invite?
    local invite
    local invited = state:wait_until(HOST_SECONDS, function()
        invite = invite_of(quest.by, state.stage)
        return invite ~= nil
    end)
    if not invited or invite == nil then
        state:give_up(string.format("no invite from %s to stage %s after %d s", quest.name, state.stage, HOST_SECONDS))
    end
    -- In a task of its own: the accept ends in the hunter's link action,
    -- which enters the world only from `free`, once this state is over.
    tasks.spawn("accept the quest host's invite", function() Party.accept(invite) end)
end

---@param quest sq.PartyQuest
---@param free sq.Free
---@return boolean started
function QuestTravel.join(quest, free)
    if not Travelling.from(free, quest.stage, function(state) enter_world(state, quest) end) then return false end
    Feed.say("Joining the quest...")
    note("quest", "%s's quest (mission %d, stage %s): on our way", quest.name, quest.asked.mission, quest.stage)
    return true
end

return QuestTravel
