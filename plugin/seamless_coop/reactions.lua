-- Where the game's events meet the policy: each hook here
-- reads its event, asks policy.lua what to do in the world as it is (the
-- latest one, at most a frame old: hooks may run on another thread and
-- make no game calls to find out) and in the state we are in, and hands
-- the answer to a state (ops/). No decision is taken here; a state that
-- can't be entered from the one we are in leaves the event to the game.

local journal = require("seamless_coop.base.journal")
local hooks = require("seamless_coop.base.hooks")
local arg = require("seamless_coop.base.arg")
local tasks = require("seamless_coop.base.tasks")
local policy = require("seamless_coop.policy")
local World = require("seamless_coop.world")
local State = require("seamless_coop.state")
local PartyQuest = require("seamless_coop.party_quest")
local Offers = require("seamless_coop.offers")
local Words = require("seamless_coop.words")
local Window = require("seamless_coop.game.window")
local QuestStart = require("seamless_coop.ops.quest_start")
local QuestTravel = require("seamless_coop.ops.quest_travel")
local Departing = require("seamless_coop.ops.departing")
local Entering = require("seamless_coop.ops.entering")
local Leaving = require("seamless_coop.ops.leaving")
local Party = require("seamless_coop.ops.party")
local Session = require("seamless_coop.game.session")
local LinkParty = require("seamless_coop.game.link_party")
local User = require("seamless_coop.game.user")
local Quest = require("seamless_coop.game.quest")
local AskedQuest = require("seamless_coop.game.asked_quest")
local Director = require("seamless_coop.game.director")
local Counter = require("seamless_coop.game.counter")
local Feed = require("seamless_coop.game.feed")
local note = journal.note

---@class sq.Reactions
local Reactions = {}

local SKIP = sdk.PreHookResult.SKIP_ORIGINAL

local function nothing() end

-- A hook runs only with the latest world of an enabled plugin.
---@param handler fun(w: sq.World, args: HookArgs): sdk.PreHookResult?
---@return fun(args: HookArgs): sdk.PreHookResult?
local function enabled(handler)
    return function(args)
        local w = World.now()
        if w == nil or not w.enabled then return end
        return handler(w, args)
    end
end

---@param counter sq.Counter
---@param posted sq.Quest
---@param stage integer
---@param free sq.Free
---@return sdk.PreHookResult?
local function travel_to_post(counter, posted, stage, free)
    local asked = AskedQuest.posted(posted)
    if asked == nil then
        note("quest", "mission %s is an investigation in stage %s: left to the game", posted:mission(), stage)
        return
    end
    if QuestTravel.post(counter, posted, asked, stage, free) then return SKIP end
end

-- A post refused because a quest goes on in its stage: the counter ended
-- as after an accept, the player told, and the offer to join that quest
-- made again. ASSUMED: ending the counter this way without a quest
-- accepted is as harmless here as for a member's post.
---@param counter sq.Counter
---@param stage integer
---@return sdk.PreHookResult?
local function refuse_post(counter, stage)
    counter:finish()
    tasks.spawn("a post refused", function()
        Feed.say(Words.already(stage))
        Offers.remind()
    end)
    return SKIP
end

-- GUIFlowGUI050001View.Flow.OrderHost.stateStart: a quest posted at the
-- counter.
---@param w sq.World
---@param args HookArgs
local function on_counter_post(w, args)
    local counter = Counter.wrap(arg.object(args[2]))
    if counter == nil then return end
    local posted, board = counter:posted()
    if posted == nil or board == nil then return end
    return policy.counter_post(w, State.now(), board, {
        start_here = function(free)
            if QuestStart.post(counter, posted:mission(), free) then return SKIP end
        end,
        ask_host = function()
            if QuestStart.ask_host(counter, posted) then return SKIP end
        end,
        travel = function(free) return travel_to_post(counter, posted, board.stage, free) end,
        already = function(stage) return refuse_post(counter, stage) end,
        game = function(why)
            if why then note("quest", "mission %s: %s: left to the game", posted:mission(), why) end
        end,
    })
end

-- The game departs late for a quest joined, at once for a quest hosted.
---@param late boolean
---@return sq.Role
local function role_of(late)
    if late then return "guest" end
    return "host"
end

---@return integer?
local function quest_stage()
    local quest = Quest.current()
    if quest == nil then return nil end
    return quest:stage()
end

-- mcHunterQuestActionController.requestQuestStartBeforeAction: the
-- hunter's departure for a quest. Ours to make only for a start we asked
-- for, as the one we asked as.
---@param w sq.World
---@param args HookArgs
local function on_departure(w, args)
    local role = role_of(arg.bool(args[3]))
    local pending = Departing.pending(role)
    if pending == nil then return end
    local in_place, why = policy.departure(w, role, quest_stage())
    if not in_place then
        note("quest", "departure left to the game: %s", why)
        pending:give_up()
        return
    end
    if not QuestStart.depart(pending) then return end
    note("quest", "departure made in place")
    return SKIP
end

-- A member that started a quest itself invites the link's members, once
-- the start has settled.
---@async
local function invite_as_member()
    tasks.sleep(0.5)
    local w = World.now()
    if w == nil then return end
    local invite, why = policy.member_invite(w)
    if not invite then
        note("quest", "%s: no invite sent", why)
        return
    end
    LinkParty.invite_to_quest_as_member()
end

-- cQuestDirector.goQuest: every quest start.
---@param w sq.World
---@param args HookArgs
local function on_go_quest(w, args)
    policy.quest_started(w, arg.bool(args[4]), Director.joining_late(), {
        game = nothing,
        keep_limit = Director.keep_member_limit,
        invite_others = function()
            Director.keep_member_limit()
            tasks.spawn("invite as a member", invite_as_member)
        end,
    })
end

-- Net_Party.addQuestInviteNotify: a quest invite the game turns into a
-- notice (anything but a field quest). Handled here, the invite gets no
-- notice: accepting it by hand while the plugin is on its way into the
-- same quest hangs the game's own accept in a loading screen (2026-11-15
-- 15:53). The notice call only writes the chat log and the notice list.
---@param w sq.World
---@param args HookArgs
local function on_quest_invite(w, args)
    local inviter, mission = User.wrap(arg.object(args[3])), arg.int(args[4])
    -- Our own invite, as the game notes it: nothing to answer.
    if inviter == nil or inviter:is_self() then return end
    local asked = AskedQuest.of(mission)
    if asked == nil then return end
    ---@type sq.QuestInvite
    local invite = { stage = asked:stage(), director_busy = Quest.current() ~= nil,
        from_host = function() return inviter:member_index() == Session.host_index() end }
    return policy.quest_invite(w, State.now(), invite, {
        game = function(why)
            if why then note("quest", "mission %d %s: left to the game", mission, why) end
        end,
        start_for_member = function(free)
            if QuestStart.for_member(asked, free) then return SKIP end
        end,
        follow_host = function()
            if not w:invite(asked) then return end
            note("quest", "the host invites to mission %d: following", mission)
            return SKIP
        end,
        hear = function()
            local quest = PartyQuest.new(inviter:id(), inviter:name(), asked, os.clock())
            w:hear(quest)
            note("quest", "%s announces mission %d in stage %s: offered", quest.name, mission, quest.stage)
            return SKIP
        end,
    })
end

-- GUI050000.search, the counter's search for quest sessions. For a guest
-- out of the host's quest, "Link Member Quests" finds nothing (the quest
-- runs in the link's session, not a quest session of its own), and is its
-- way back into that quest.
---@param w sq.World
---@param args HookArgs
local function on_quest_search(w, args)
    if not Counter.searches_link(arg.object(args[3])) then return end
    local invited, outside = policy.rejoinable(w, State.now())
    if invited ~= nil and outside ~= nil and QuestStart.join(invited, "link member quests", outside) then return SKIP end
end

---@param w sq.World
---@param now sq.Now
local function on_link_left(w, now)
    local free = policy.stays_after_link(w, now)
    if free == nil or not Leaving.from(free) then return end
    journal.later("leave", "link left: its leave load skipped")
    return SKIP
end

---@param w sq.World
---@param now sq.Now
local function on_link_accepted(w, now)
    local free, why = policy.enters_in_place(w, now, LinkParty.accepted_stage())
    if free ~= nil and Entering.from(free) then return SKIP end
    if why then journal.later("join", "%s: left to the game", why) end
end

-- mcHunterQuestActionController.requestLinkPartyAction: true after an
-- accept, false after a leave. Called on another thread than the frame's:
-- fields only.
---@param w sq.World
---@param args HookArgs
local function on_link_action(w, args)
    local now = State.now()
    if arg.bool(args[3]) then return on_link_accepted(w, now) end
    return on_link_left(w, now)
end

-- cGameJumper.requestSceneJump.
---@param w sq.World
---@param args HookArgs
local function on_scene_jump(w, args)
    local stage, situation = arg.int(args[3]), arg.int(args[4])
    return policy.scene_jump(w, State.now(), stage, situation, {
        prepare_session = function()
            journal.later("party", "travel to stage %d (situation %d) requested", stage, situation)
            Party.prepare_session()
        end,
        stay = function(free)
            if not Leaving.from(free) then return end
            journal.later("leave", "the host ended the link: the jump home skipped")
            return SKIP
        end,
        game = function(why)
            if why then journal.later("leave", "%s: left to the game", why) end
        end,
    })
end

-- ChatManager.addNetworkLog, from Net_Party.recvInvitePartySync once the
-- invite is stored: only the log entry is skipped, the invite is kept.
---@param w sq.World
---@param args HookArgs
local function on_network_log(w, args)
    if not policy.hides_game_notice(w, arg.int(args[3])) then return end
    journal.later("party", "the game's notice of an environment invite skipped: offered by us")
    return SKIP
end

-- cGUISystemModuleNotifyWindow.requestNotifyWindow: a window of the game
-- is about to open.
---@param _w sq.World
---@param args HookArgs
local function on_notify_window(_w, args)
    local window = Window.read(arg.object(args[3]))
    if window == nil then return end
    local answer, why = policy.window(window)
    if answer == nil then
        if why then journal.later("window", "%s: %s", window:describe(), why) end
        return
    end
    journal.later("window", "%s: not opened, answered %d", window:describe(), answer)
    window:answer(answer)
    return SKIP
end

function Reactions.install()
    hooks.on("app.GUIFlowGUI050001View.Flow.OrderHost", "stateStart()", enabled(on_counter_post))
    hooks.on("app.mcHunterQuestActionController", "requestQuestStartBeforeAction(System.Boolean)", enabled(on_departure))
    hooks.on("app.mcHunterQuestActionController", "requestLinkPartyAction(System.Boolean)", enabled(on_link_action))
    hooks.on("app.cQuestDirector", "goQuest(System.Boolean, System.Boolean, System.Boolean, System.Boolean)", enabled(on_go_quest))
    hooks.on("app.GUI050000", "search(app.net_quest_session.cSearchQuestSessionInfo, app.MissionIDList.ID)", enabled(on_quest_search))
    hooks.on("app.Net_Party", "addQuestInviteNotify(app.Net_UserInfo, app.MissionIDList.ID)", enabled(on_quest_invite))
    hooks.on("app.cGameJumper",
        "requestSceneJump(app.FieldDef.STAGE, app.WarpDef.SITUATION_TYPE, app.cGameSceneFadeParam, app.GimmickDef.ID)", enabled(on_scene_jump))
    hooks.on("app.ChatManager", "addNetworkLog(app.ChatDef.LOG_ID, System.Guid, app.net_session_manager.SESSION_TYPE)", enabled(on_network_log))
    hooks.on("ace.cGUISystemModuleNotifyWindow`2<app.GUIID.ID,app.GUIFunc.TYPE>", "requestNotifyWindow(ace.cGUINotifyWindowInfo)", enabled(on_notify_window))
end

return Reactions
