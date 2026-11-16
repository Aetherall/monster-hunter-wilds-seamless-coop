local memory = require("seamless_coop.base.memory")
local Flag = require("seamless_coop.base.flag")
local managers = require("seamless_coop.game.managers")
local Missions = require("seamless_coop.game.missions")
local Session = require("seamless_coop.game.session")
local Quest = require("seamless_coop.game.quest")

-- Quest data handed to the director, kept from the collector.
---@class sq.Director.Kept
---@field objects REManagedObject[]
---@type sq.Director.Kept
local kept = memory.keep("director", { objects = {} })

-- Raised while our own late join makes the director's calls.
local joining = Flag.new()

-- cQuestSceneLoading's state once its scene jump runs.
local SCENE_JUMP = 1
-- The mission activator's phase when it takes requests.
local ACTIVATOR_UPDATE = 6
local FADE_APP, FADE_STORY = 1 << 15, 1 << 18

---@return REManagedObject?
local function flow() return Missions.director():get_field("_CurFlow") end

-- The quest director (app.cQuestDirector): the quest we are in and the
-- flow it is at.
---@class sq.Director
local Director = {}

---@alias sq.DirectorFlow "cQuestPlaying"|"cQuestLeaveShowing"|"cQuestLeaveShowingBefore"|"cQuestSuccessFreePlayTime"|"cQuestSceneLoading"

---@param name string?
---@param expected sq.DirectorFlow
---@return boolean
function Director.flow_matches(name, expected) return name == expected end

---@return string?
function Director.flow_name()
    local current = flow()
    return current and current:get_type_definition():get_name()
end

---@param expected sq.DirectorFlow
---@return boolean
function Director.at(expected) return Director.flow_matches(Director.flow_name(), expected) end

-- The stage the quest's return load would bring us back to.
---@return integer
function Director.return_stage() return Missions.director():get_field("_QuestBeforeStage") end

-- The director's member limit for a quest inside the link: the session's
-- own. As the quest starts the host sends the limit to the server, which
-- answers an error for any other value, and the game leaves the session.
function Director.keep_member_limit()
    local limit = Session.member_limit()
    if limit ~= 0 then Missions.director():set_field("_MaxJoinNum", limit) end
end

---@param asked sq.AskedQuest
local function accept(asked)
    local data = asked:quest():raw()
    kept.objects[#kept.objects + 1] = data
    Missions.director():call("acceptQuest(app.cActiveQuestData, app.cQuestAcceptArg, System.Boolean, System.Boolean)", data, nil, false, false)
    Director.keep_member_limit()
end

---@param late boolean
local function request_start_to_hunter(late)
    managers.method("app.GUIUtilApp.QuestUtil", "requestQuestStartToPL(System.Boolean)"):call(nil, late)
end

-- The host's start of a quest without the counter: the quest accepted,
-- the hunter's departure (which the plugin cuts), the director's goQuest.
-- No session is created or left.
---@param asked sq.AskedQuest
function Director.start(asked)
    accept(asked)
    request_start_to_hunter(false)
    Missions.director():call("goQuest(System.Boolean, System.Boolean, System.Boolean, System.Boolean)", false, false, false, false)
end

-- A member's late departure for the host's quest, as the departure
-- preparation's "depart" does it (GUI050002.questDepartForLateJoin).
---@param asked sq.AskedQuest
function Director.join_late(asked)
    accept(asked)
    request_start_to_hunter(true)
    Session.go_quest_late()
    local object = Missions.director()
    local _ <close> = joining:raise()
    object:call("goQuest(System.Boolean, System.Boolean, System.Boolean, System.Boolean)", false, false, true, false)
end

---@return boolean
function Director.joining_late() return joining:raised() end

-- `quest` on the director for the time of `call` only, with the session's
-- member limit: what a quest invite is built from.
---@param quest sq.Quest
---@param call fun()
---@return boolean ok, any err
function Director.lend(quest, call)
    local object = Missions.director()
    Director.keep_member_limit()
    object:set_field("_QuestData", quest:raw())
    local ok, err = pcall(call)
    object:set_field("_QuestData", nil)
    return ok, err
end

function Director.cancel()
    managers.method("app.MissionUtil", "requestQuestCancel(System.Boolean, System.Boolean, System.Boolean)"):call(nil, true, false, false)
end

---@param manager REManagedObject
---@param id integer
---@return boolean
local function mission_is_here(manager, id)
    local list = manager:get_field("_MissionGoList")
    local items = list:get_field("_items")
    for i = 0, list:get_field("_size") - 1 do
        local entry = items:get_element(i)
        if entry and entry:get_field("missionId") == id then return true end
    end
    return false
end

-- A board quest's mission is loaded by the load's mission phases; in the
-- field the game does it for field quests with reqLoadQuestMission, which
-- queues the prefab for the mission activator's UPDATE phase.
---@return string what
function Director.load_mission()
    local quest = Quest.current()
    if quest == nil then return "no quest" end
    local manager, id = Missions.manager(), quest:mission()
    if mission_is_here(manager, id) then return string.format("mission %s already here", id) end
    local phase = manager:get_field("<InstMissionActivator>k__BackingField"):get_field("<_Phase>k__BackingField")
    if phase ~= ACTIVATOR_UPDATE then
        return string.format("mission %s not here; activator phase %s, left alone", id, phase)
    end
    manager:call("reqLoadQuestMission(app.MissionTypeList.TYPE, app.MissionIDList.ID)", quest:type(), id)
    return string.format("mission %s (type %s) requested", id, quest:type())
end

---@return boolean?
function Director.mission_loaded()
    local quest = Quest.current()
    if quest == nil then return nil end
    local manager = Missions.manager()
    return manager:call("getEnableMissionController(app.MissionIDList.ID)", quest:mission()) ~= nil
        and manager:call("checkLoadingMission()") == false and manager:call("checkLoadingMissionObjective()") == false
end

-- A quest accepted during a join puts the director in cQuestSceneLoading,
-- which waits for a scene jump to begin (STARTWAIT) and to end
-- (SCENE_JUMP). No jump comes in place: moved to SCENE_JUMP, its next
-- update sees the transition at rest and goes on.
---@return string what
function Director.pass_scene_loading()
    local current = flow()
    if current == nil then return "no quest" end
    local name = current:get_type_definition():get_name()
    if not Director.flow_matches(name, "cQuestSceneLoading") then return name end
    local state = current:get_field("_State")
    if state ~= 0 then return name .. " state " .. tostring(state) end
    current:set_field("_State", SCENE_JUMP)
    return name .. " STARTWAIT -> SCENE_JUMP"
end

-- The game's own skip of the free time after a clear, which it takes once
-- every member has asked.
function Director.skip_free_time() Missions.director():call("QuestReturnSkip()") end

-- cQuestLeaveShowingBefore waits a timer before the abandon's notice (10 s
-- without the retire action, 1 s natively): cut.
function Director.cut_abandon_wait()
    local current = flow()
    if current ~= nil then current:set_field("_ShowingBeforeTimer", 0.0) end
end

-- cQuestLeaveShowing shows the "quest abandoned" notice and goes to the
-- result from the notice's end callback: called at once.
function Director.end_abandon_notice()
    local current = flow()
    if current ~= nil then current:call("<update>b__2_0(System.Object, ace.GUIBaseCore)", nil, nil) end
end

---@return REManagedObject
local function result_param() return Missions.director():get_field("<Param>k__BackingField") end

-- The result's form of a field hunt's end: no fade, no result or reward
-- screens, the result list on the HUD, rewards received by themselves.
---@return boolean
function Director.result_is_seamless() return result_param():get_field("IsResultSeamless") end
function Director.make_result_seamless() result_param():set_field("IsResultSeamless", true) end
---@return boolean
function Director.host_changed() return result_param():get_field("IsHostChangeQuestSession") end

-- Set at the quest's end and put back by the load: "the quest is finishing
-- until its objects are unloaded", and a fade the result may have left.
function Director.finish_end()
    local manager = Missions.manager()
    if manager:get_field("_IsWaitQuestGameObjectUnload") then
        manager:call("setIsWaitQuestGameObjectUnload(System.Boolean)", false)
    end
    local fade = managers.single("app.FadeManager")
    local bits = fade:get_field("_FadeBit")
    if bits & FADE_APP ~= 0 then fade:call("endApp(System.Single, ace.cFadeRequest.FADE_PRIORITY)", 0.3, 1) end
    if bits & FADE_STORY ~= 0 then fade:call("endStory(System.Single, ace.cFadeRequest.FADE_PRIORITY)", 0.3, 1) end
end

return Director
