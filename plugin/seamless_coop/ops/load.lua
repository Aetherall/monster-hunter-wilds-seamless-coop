-- A load made in place: what the game's load does for a join or a return,
-- done where the hunter stands, in the load's order and with its calls.
-- A Load belongs to the state that makes it (state.lua) and each of its
-- steps takes the frames it needs; the states (the other files of ops/)
-- are sequences of them.
--
-- A load into a host's world or quest takes the host's enemies
-- (ops/taking.lua).

local journal = require("seamless_coop.base.journal")
local Enemy = require("seamless_coop.game.enemy")
local Environment = require("seamless_coop.game.environment")
local Taking = require("seamless_coop.ops.taking")
local delegates = require("seamless_coop.game.delegates")
local Session = require("seamless_coop.game.session")
local Director = require("seamless_coop.game.director")
local Hunter = require("seamless_coop.game.hunter")
local SessionType = Session.Type
local note = journal.note

local LoadFlow = Environment.LoadFlow

local ENVIRONMENT_SECONDS = 20
local SYNC_SECONDS = 40
local MISSION_SECONDS = 20
local LAYOUT_SECONDS = 15
local SESSION_SECONDS = 20
local FIELD_SECONDS = 10
-- Frames the game's managers take to see a change of ours.
local SETTLE_FRAMES = 5

-- Until when the session's sync may take: what telling the session we
-- wait for it (notify) hands to the steps that wait.
---@class sq.SyncDeadline
---@field at number

-- When the quest's mission was asked for: what the host's sync hands to
-- the layout step, which waits for that mission.
---@class sq.MissionRequest
---@field at number

---@class sq.Load
---@field private state sq.State
local Load = {}
Load.__index = Load

---@private
---@param state sq.State
---@return sq.Load
function Load.by(state)
    ---@type sq.Load
    local self = setmetatable({}, Load)
    self.state = state
    return self
end

-- A load into a world or a quest: what was taken from the host of the
-- one before is over.
---@param state sq.State
---@return sq.Load
function Load.into(state)
    Taking.forget()
    return Load.by(state)
end

---@param state sq.State
---@return sq.Load
function Load.out(state) return Load.by(state) end

---@private
---@async
---@param frames integer?
function Load:wait(frames)
    for _ = 1, frames or 1 do self.state:frame() end
end

-- A departure is cut from inside the game's own call; its caller still has
-- the session's and the quest director's goQuest to run.
---@async
function Load:settle() self:wait(2) end

-- The load's phase 3 on a host: the explored field's schedule goes to the
-- save and the game picks the quest's field role.
---@async
function Load:host_field()
    Environment.clean_up_field()
    local before, after = Environment.choose_role()
    note("join", "host: cleanUpExField, field role %s -> %s", before, after)
    self:wait()
end

-- Our field's role for what we enter.
--   "world"  a guest of the host's explored field
--   "quest"  the game's own choice, which must be a guest's
---@private
---@param whose "world"|"quest"
function Load:take_role(whose)
    if whose == "world" then
        Environment.become_explore_guest()
        return
    end
    local before, chosen = Environment.choose_role()
    note("join", "field role %s -> %s", before, chosen)
    if not Environment.is_guest() then
        Environment.set_role(before)
        self.state:stop("role " .. tostring(chosen) .. " is not a guest's; put back")
    end
end

-- One poll per frame, until `done(first)` answers true or `deadline` has
-- passed. `first` is true for the first poll only.
---@private
---@async
---@param deadline number
---@param done fun(first: boolean): boolean
---@return boolean done, integer polls
function Load:poll(deadline, done)
    local polls = 0
    for poll in self.state:frames() do
        polls = poll
        if done(poll == 1) then return true, polls end
        if os.clock() > deadline then break end
    end
    return false, polls
end

---@param done boolean
---@return string
local function outcome(done)
    if done then return "done" end
    return "timed out"
end

---@async
---@param whose "world"|"quest"
function Load:environment(whose)
    self:take_role(whose)
    local done, polls = self:poll(os.clock() + ENVIRONMENT_SECONDS, Environment.sync_done)
    note("join", "environment sync %s after %d polls", outcome(done), polls)
    self:wait()
end

-- The session told we wait for its sync. Inside a link's session that
-- puts the sequence back to the link's: a quest's is QUEST.
---@async
---@param quest boolean
---@return sq.SyncDeadline
function Load:notify(quest)
    note("join", "notityWaitSync %s", Session.notify_wait_sync())
    if quest and Session.resume_quest_sequence() then note("join", "session sequence put back to QUEST") end
    ---@type sq.SyncDeadline
    local deadline = { at = os.clock() + SYNC_SECONDS }
    self:wait()
    return deadline
end

-- The host's LoadAfter waiter, when goQuest registered it: waits for the
-- members who depart with us, then calls startQuest. Alone, goQuest has
-- started the quest itself and registers nothing: no wait.
---@private
---@async
---@param deadline sq.SyncDeadline
---@return string what
function Load:wait_for_members(deadline)
    if not delegates.waits(Session.join_sync_method()) then return "not needed" end
    local done = self:poll(deadline.at, Session.join_sync_done)
    if not done then self.state:stop("waitCompleteJoinSync") end
    return "waited for"
end

---@async
---@param deadline sq.SyncDeadline
---@return sq.MissionRequest
function Load:host_sync(deadline)
    local waited = self:wait_for_members(deadline)
    note("join", "host: members' sync %s; quest mission: %s", waited, Director.load_mission())
    ---@type sq.MissionRequest
    local request = { at = os.clock() }
    self:wait()
    return request
end

---@private
---@async
---@param request sq.MissionRequest
function Load:wait_for_mission(request)
    local deadline = request.at + MISSION_SECONDS
    for _ in self.state:frames() do
        local loaded = Director.mission_loaded()
        if loaded == nil then self.state:stop("the quest left the director") end
        if loaded then break end
        if os.clock() > deadline then self.state:stop("the quest's mission did not load") end
    end
end

-- A quest with a field schedule of its own (an investigation) makes the
-- host wait for its members' load-flow requests, which members that do
-- not load never send: skipped, once the managers have seen the change.
-- A quest of the quest table has no such flow (NOT_EX).
---@param members boolean   link members are in our session
---@param poll integer
---@return boolean skipped
local function skip_wait_for_members(members, poll)
    return members and poll >= SETTLE_FRAMES and Environment.skip_wait_for_members()
end

---@param frame integer
---@param layout integer
---@param load sq.LoadFlow
---@return boolean
local function layout_running(frame, layout, load)
    return frame < SETTLE_FRAMES or layout ~= 0 or load < LoadFlow.COMPLETED
end

---@private
---@async
---@param started number
function Load:run_layout_change(started)
    for frame in self.state:frames() do
        Environment.update_field_load(frame == 1)
        if skip_wait_for_members(true, frame) then note("join", "host: field load flow: the wait for the link's members skipped") end
        local layout, load = Enemy.layout_change_flow(), Environment.load_flow()
        if not layout_running(frame, layout, load) or os.clock() >= started + LAYOUT_SECONDS then
            note("join", "host: layout change flow %s, field load flow %s after %d frames; quest flow: %s", layout, load, frame,
                Director.pass_scene_loading())
            break
        end
    end
end

-- The load's scene-load-end on a host, once the quest's mission is there:
-- the field set up for its role, then the mission's enemy tags and a
-- CLEAR_ALL layout change, which replaces every enemy by the quest's field
-- in place.
---@async
---@param request sq.MissionRequest
function Load:host_layout(request)
    self:wait_for_mission(request)
    Environment.set_up_field()
    local how, started = Enemy.scene_load_end(), os.clock()
    note("join", "host: field set up for the quest %.1f s after its mission was asked for, %s", started - request.at, how)
    self:wait()
    self:run_layout_change(started)
    self:wait()
end

-- The host change of a late join also converted this field's own large
-- monsters, which the host does not have: its snapshot never names them.
---@private
---@param taking sq.Taking
function Load:drop_unnamed(taking)
    local found = taking:unnamed()
    if not taking:any() then
        note("join", "%d replicas the host did not name, left alone: %s", #found, Enemy.labels(found))
        return
    end
    note("join", "%d replicas the host did not name, removed: %s", #found, Enemy.labels(found))
    Enemy.remove_all(found)
end

-- A guest's late join of the session. Before the host's snapshot arrives,
-- the conversion the join started (self index) is completed with the
-- game's host-migration step; the late join's create phase then takes the
-- enemies already here (ops/taking.lua) instead of refusing them.
---@async
---@param quest boolean
---@param deadline sq.SyncDeadline
function Load:late_join(quest, deadline)
    local host = Session.host_index()
    Enemy.change_host(SessionType.QUEST, host)
    local taking = Taking.begin(host)
    self:wait()
    local done, polls = self:poll(deadline.at, Session.late_join_done)
    if not done then self.state:stop("waitComplateLateJoin") end
    note("join", "late join done after %d polls: %s", polls, taking:describe())
    if quest then note("join", "quest mission: %s", Director.load_mission()) end
    note("join", "quest flow: %s", Director.pass_scene_loading())
    self:wait()
    self:drop_unnamed(taking)
    self:wait()
end

function Load.fade_in() delegates.fade_in() end

-- A quest's start, and our own field's return, populate the field's local
-- animals over the ones already here.
---@param kind string   the journal's
function Load.remove_duplicates(kind)
    local found = Enemy.duplicates()
    if #found == 0 then return end
    note(kind, "%d local enemies exist twice, removed: %s", #found, Enemy.labels(found))
    Enemy.remove_all(found)
end

-- Where we are with the quest session: out of it ("left"), in it for
-- good because it is the link's and the link goes on ("kept"), or still
-- on our way out ("leaving").
---@param leaving_link boolean
---@return "left"|"kept"|"leaving"
local function session_state(leaving_link)
    if not Session.multiplay() then return "left" end
    if Session.linked() and not leaving_link then return "kept" end
    return "leaving"
end

---@private
---@param deadline number
---@param reason string
function Load:stop_after(deadline, reason)
    if os.clock() > deadline then self.state:stop(reason) end
end

-- After a quest's end or a link's leave: waits until the session is left,
-- or tells it is kept (a quest that ran inside the link's session ends
-- with the session kept: cQuestSession.endQuest, by link-party sync), then
-- a few frames for the managers' own updates to see it.
---@async
---@param leaving_link boolean
---@return boolean kept
function Load:session_left(leaving_link)
    local deadline, quiet, kept = os.clock() + SESSION_SECONDS, 0, false
    for _ in self.state:frames() do
        local state = session_state(leaving_link)
        kept = kept or state == "kept"
        if state == "leaving" then
            self:stop_after(deadline, "still in the quest session after " .. SESSION_SECONDS .. " s")
        else
            quiet = quiet + 1
        end
        if quiet >= SETTLE_FRAMES then break end
    end
    return kept
end

---@private
---@async
---@param hosting_members boolean   link members are still in our session
function Load:run_field_load(hosting_members)
    local deadline = os.clock() + FIELD_SECONDS
    self:wait()
    for poll in self.state:frames() do
        Environment.update_field_load(poll == 1)
        if skip_wait_for_members(hosting_members, poll) then
            note("leave", "field load flow: the wait for the link's members skipped")
        end
        local flow = Environment.load_flow()
        if flow >= LoadFlow.COMPLETED or os.clock() >= deadline then
            note("leave", "field load flow %s after %d polls", flow, poll)
            break
        end
    end
end

-- The host's schedule monsters, which no layout change knows about; our
-- own come back with our schedule. Not for the host of what ends.
function Load:drop_host_schedule()
    local found = Enemy.of_schedule()
    note("leave", "%d schedule enemies of the host removed: %s", #found, Enemy.labels(found))
    Enemy.remove_all(found)
end

-- Our own field back, as the return load brings it: the explored field's
-- schedule back from the save and started, and the CLEAR_ALL layout
-- changes that replace the enemies in place.
---@async
---@param session_kept boolean   the link's session goes on, with its members in it
function Load:restore_field(session_kept)
    Environment.clean_up_field()
    local before, after = Environment.choose_role()
    note("leave", "%s; cleanUpExField, field role %s -> %s", session_kept and "link session kept" or "session left", before, after)
    Environment.clear_override()
    Environment.set_up_field()
    Enemy.scene_load_end()
    self:run_field_load(session_kept)
end

-- Once our own field is back: what its return populated twice is
-- removed, and an abandon's pose ended.
function Load.settle_home()
    Load.remove_duplicates("leave")
    Hunter.release_retire_pose()
end

return Load
