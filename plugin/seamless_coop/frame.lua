-- What the plugin does by itself, every frame, when the world calls for
-- it: it asks policy.lua and hands the answer on. No decision is taken
-- here.

local journal = require("seamless_coop.base.journal")
local policy = require("seamless_coop.policy")
local State = require("seamless_coop.state")
local QuestStart = require("seamless_coop.ops.quest_start")
local Party = require("seamless_coop.ops.party")
local Offers = require("seamless_coop.offers")
local note = journal.note

local Frame = {}

local NEIGHBOUR_SECONDS = 1
---@type number
local neighbours_at = 0

local function nothing() end

---@param w sq.World
---@param now sq.Now
local function follow_host(w, now)
    policy.follow(w, now, {
        wait = nothing,
        forget = function(invited)
            note("quest", "the host did not start mission %d: not followed", invited.mission)
            w:forget_invitation()
        end,
        join = function(invited, free) QuestStart.join(invited, "the host's invite", free) end,
    })
end

-- The quest of the host we stand with, told to us before we were in its
-- world, becomes the quest the host invited us to: joined like one.
---@param w sq.World
local function follow_heard_quest(w)
    local quest = policy.host_quest_heard(w)
    if quest == nil or not w:invite(quest.asked) then return end
    note("quest", "%s plays mission %d, announced earlier: following", quest.name, quest.asked.mission)
end

---@param w sq.World
local function after_travel(w)
    local travelled = w.travelled
    if travelled == nil or not policy.invite_after_travel(w) then return end
    note("party", "travelled from stage %s to %s in a link party: inviting it", travelled.from, w.stage)
    Party.invite_after_travel(w.stage)
end

-- Members met in a stage are invited once while they stay.
---@param w sq.World
local function invite_neighbours(w)
    if neighbours_at + NEIGHBOUR_SECONDS > os.clock() then return end
    neighbours_at = os.clock()
    policy.neighbour(w, {
        unknown = nothing,
        nobody = Party.nobody_near,
        met = function(member)
            if Party.invited_to(w.stage) then return end
            note("party", "%s is in our stage, outside our environment: inviting the party", member.name)
            Party.invite_here(w.stage)
        end,
    })
end

---@param w sq.World
function Frame.react(w)
    local now = State.now()
    if not w.enabled then
        Offers.reconcile(w, now)
        return
    end
    follow_heard_quest(w)
    follow_host(w, now)
    after_travel(w)
    invite_neighbours(w)
    Offers.reconcile(w, now)
end

return Frame
