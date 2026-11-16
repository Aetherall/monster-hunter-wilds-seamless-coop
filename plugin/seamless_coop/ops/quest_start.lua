-- The ways a quest is started inside an Environment Link, in the link's
-- own session, so that nobody leaves the link and nobody loads. Each one
-- asks the game for the start and waits for the hunter's departure
-- (ops/departing.lua), which `depart` then makes in place.

local journal = require("seamless_coop.base.journal")
local Departing = require("seamless_coop.ops.departing")
local HostedQuest = require("seamless_coop.ops.hosted_quest")
local JoinedQuest = require("seamless_coop.ops.joined_quest")
local LinkParty = require("seamless_coop.game.link_party")
local Quest = require("seamless_coop.game.quest")
local Director = require("seamless_coop.game.director")
local Counter = require("seamless_coop.game.counter")
local note = journal.note

local QuestStart = {}

-- The host's counter: straight to the accept; the game's own accept and
-- departure follow.
---@param counter sq.Counter
---@param mission integer
---@param free sq.Free
---@return boolean started
function QuestStart.post(counter, mission, free)
    if not Departing.from(free, "host", mission) then return false end
    counter:accept()
    note("quest", "mission %d posted inside the link's session", mission)
    return true
end

---@param asked sq.AskedQuest
---@param free sq.Free
---@return boolean started
function QuestStart.for_member(asked, free)
    if not Departing.from(free, "host", asked.mission, function() Director.start(asked) end) then return false end
    note("quest", "a member asks for mission %d: started in the link's session", asked.mission)
    return true
end

-- A guest's join of the quest the host invited to, as a late departure.
-- From `outside` (a guest that left the quest alone), the counter it may
-- stand at is closed first.
---@param invited sq.Invitation
---@param how string   the journal's
---@param from sq.Free|sq.Outside
---@return boolean started
function QuestStart.join(invited, how, from)
    local rejoining = from:is("outside")
    local entered = Departing.from(from, "guest", invited.mission, function(departing)
        if rejoining then
            Counter.close()
            departing:sleep(0.2)
        end
        Director.join_late(invited.quest)
    end)
    if not entered then return false end
    invited:mark_joined()
    note("quest", "%s while the host plays mission %d: joining", how, invited.mission)
    return true
end

-- A member's counter: the quest asked of the host. The invite is built
-- from the director's quest, which is lent to it for the call only. A
-- quest accepted here and left waiting for the host is "departure
-- preparation" to the game, whose HUD then reads an order it never got
-- (crash, 2026-11-15 16:08:51).
---@param counter sq.Counter
---@param quest sq.Quest
---@return boolean asked
function QuestStart.ask_host(counter, quest)
    local mission = quest:mission()
    local ok, err = Director.lend(quest, LinkParty.invite_to_quest_as_member)
    if not ok then
        note("error", "mission %d not asked of the host, left to the game: %s", mission, err)
        return false
    end
    counter:finish()
    note("quest", "mission %d posted by a member: asked of the session's host", mission)
    return true
end

-- The hunter's departure made in place, from inside the game's call to
-- the departure action (which is then skipped); its caller still has the
-- session's and the director's goQuest to run. As the one the start was
-- asked as: the quest we host, or the host's quest we join. False with no
-- quest on the director.
---@param pending sq.Departing
---@return boolean entered
function QuestStart.depart(pending)
    local quest = Quest.current()
    if quest == nil then return false end
    if pending.role == "host" then return HostedQuest.from(pending, quest) end
    return JoinedQuest.from(pending, quest)
end

return QuestStart
