-- How the game's own ending of a quest is shaped when that end is ours
-- (an OwnEnd): no return jump, no session leave, a field hunt's result,
-- no retire action, no wait and no notice at an abandon. The game's
-- ending runs in all cases (rewards, session, missions).

local journal = require("seamless_coop.base.journal")
local hooks = require("seamless_coop.base.hooks")
local arg = require("seamless_coop.base.arg")
local Flag = require("seamless_coop.base.flag")
local settings = require("seamless_coop.base.settings")
local State = require("seamless_coop.state")
local OwnEnd = require("seamless_coop.ops.own_end")
local Session = require("seamless_coop.game.session")
local Director = require("seamless_coop.game.director")
local note = journal.note

local Cut = OwnEnd.Cut
local SKIP = sdk.PreHookResult.SKIP_ORIGINAL
-- mcHunterQuestActionController.QUEST_ACTION_TYPE.
local QUEST_ACTION_RETIRE = 2

-- Raised while the game runs cQuestDirector.requestQuestCancel.
local cancelling = Flag.new()

local Ending = {}

-- Development setting: no free time after a clear.
---@param ending sq.OwnEnd
local function skip_free_time(ending)
    if not settings.values.skip_free_time or ending:free_time_skipped() then return end
    if not Director.at("cQuestSuccessFreePlayTime") then return end
    ending:skip_free_time()
    Director.skip_free_time()
    note("leave", "development: the free time after the clear skipped")
end

-- cQuestLeaveShowingBefore waits before the "quest abandoned" notice.
---@param ending sq.OwnEnd
---@param flow string?
local function cut_wait(ending, flow)
    if not Director.flow_matches(flow, "cQuestLeaveShowingBefore") or ending:has_cut(Cut.WAIT) then return end
    ending:cut(Cut.WAIT)
    Director.cut_abandon_wait()
    note("leave", "quest abandoned: the wait before its notice cut")
end

-- cQuestLeaveShowing shows the notice: ended at once, by its own end
-- callback, whose later call by the game is refused (on_leave_notice_end).
-- Our call must come before the cut is recorded, or it is refused too.
---@param ending sq.OwnEnd
---@param flow string?
local function cut_notice(ending, flow)
    if not Director.flow_matches(flow, "cQuestLeaveShowing") or ending:has_cut(Cut.NOTICE) then return end
    Director.end_abandon_notice()
    ending:cut(Cut.NOTICE)
    note("leave", "quest abandoned: its notice cut, on to the result")
end

-- An abandon's showing flows are isQuestEndShowing to the game: HUD
-- hidden, hunter held. Once the retire action was skipped, they are cut.
---@param ending sq.OwnEnd
local function cut_abandon_showing(ending)
    if not ending:has_cut(Cut.RETIRE) then return end
    local flow = Director.flow_name()
    cut_wait(ending, flow)
    cut_notice(ending, flow)
end

---@param ending sq.OwnEnd
function Ending.shape(ending)
    skip_free_time(ending)
    cut_abandon_showing(ending)
end

local function yes() return true end
local function no() return false end

---@param answer fun(quest: sq.InQuest): any
---@return any
local function in_quest(answer)
    return State.now():when({ hosted = answer, joined = answer })
end

-- Whether the state we are in brings the field back in place, so that no
-- jump back is to be made.
---@return boolean
local function keeps_us_here()
    ---@param quest sq.InQuest
    local function cut(quest) return quest:cut_return_jump() end
    return State.now():match({
        free = no,
        entering = no,
        departing = no,
        leaving = yes,   -- our field is on its way back
        outside = yes,   -- the host's is
        travelling = no,
        hosted = cut,
        joined = cut,
    })
end

-- The end that is ours to shape: of the quest we are in, while it is
-- played.
---@return sq.OwnEnd?
local function shaped_end()
    ---@param quest sq.InQuest
    local function of(quest) return quest:shaped_end() end
    return in_quest(of)
end

-- The end that is ours, of the quest we are in, played or over.
---@return sq.OwnEnd?
local function own_end()
    ---@param quest sq.InQuest
    local function of(quest) return quest:ending() end
    return in_quest(of)
end

-- cQuestDirector.isSceneJumpQuestEnd: the quest's last flow asks it and,
-- on true, requests the jump back to the stage the quest was left from.
-- May run on any thread: it only counts.
---@param retval lightuserdata
local function on_scene_jump_quest_end(retval)
    if arg.bool(retval) and keeps_us_here() then return arg.answer(false) end
end

-- Net_SessionService.leaveSession: cQuestDirector.requestQuestCancel, for
-- a quest being played, leaves the quest session whenever it is a
-- multiplayer one, which inside a link ends the link. Skipped, and the
-- cancel's own flows then end the quest as a clear's do, session kept.
---@param args HookArgs
local function on_leave_session(args)
    local ending = shaped_end()
    if not cancelling:raised() or ending == nil then return end
    if arg.int(args[3]) ~= Session.Type.QUEST or not Session.linked() then return end
    ending:keep_session()
    Director.make_result_seamless()
    journal.later("leave", "quest abandoned inside the link: its session leave skipped")
    return SKIP
end

-- cQuestClear.enter decides the result's form: seamless only for a field
-- quest in a link. A quest whose end is ours gets it, whatever it is.
local function on_quest_clear_entered()
    if shaped_end() == nil or not Session.linked() then return end
    if Director.host_changed() or Director.result_is_seamless() then return end
    Director.make_result_seamless()
    journal.later("leave", "quest cleared: seamless result")
end

-- cQuestResult.enter: a cancel's flows put IsResultSeamless back to false
-- before cQuestResult, which reads it: set again as it is entered.
local function on_quest_result_enter()
    local ending = shaped_end()
    if ending == nil or not Session.linked() or not ending:session_kept() then return end
    Director.make_result_seamless()
    journal.later("leave", "quest abandoned: seamless result")
end

-- mcHunterQuestActionController.requestQuestActionByType(RETIRE), asked by
-- PlayerManager.evQuestFlowChanged once a cancel's flows run. The retire
-- action holds the hunter for the 4 s of the cancel's showing flows,
-- which run on their own timers, not on the action: none, the hunter
-- keeps control.
---@param args HookArgs
local function on_quest_action(args)
    local ending = shaped_end()
    if ending == nil or not Session.linked() or arg.int(args[3]) ~= QUEST_ACTION_RETIRE then return end
    if not ending:has_cut(Cut.RETIRE) then
        ending:cut(Cut.RETIRE)
        journal.later("leave", "quest abandoned: the retire action skipped, the hunter keeps control")
    end
    return SKIP
end

-- cQuestLeaveShowing's notice end callback: after we called it ourselves,
-- the notice's own would start a second result. Refused once.
local function on_leave_notice_end()
    local ending = own_end()
    if ending == nil or not ending:has_cut(Cut.NOTICE) or ending:has_cut(Cut.NOTICE_END) then return end
    ending:cut(Cut.NOTICE_END)
    return SKIP
end

function Ending.install()
    hooks.on("app.cQuestLeaveShowing", "<update>b__2_0(System.Object, ace.GUIBaseCore)", on_leave_notice_end)
    hooks.on("app.mcHunterQuestActionController",
        "requestQuestActionByType(app.mcHunterQuestActionController.QUEST_ACTION_TYPE, System.Action)", on_quest_action)
    hooks.on("app.cQuestDirector", "isSceneJumpQuestEnd()", nil, on_scene_jump_quest_end)
    hooks.on("app.cQuestDirector",
        "requestQuestCancel(System.Boolean, System.Boolean, System.Boolean, System.Boolean, System.Boolean)",
        function() cancelling:raise() end, function() cancelling:lower() end)
    hooks.on("app.Net_SessionService",
        "leaveSession(app.net_session_manager.SESSION_TYPE, System.Action`2<System.Boolean,app.NETWORK_ERROR_CODE>, System.Boolean)", on_leave_session)
    hooks.on("app.cQuestClear", "enter", nil, on_quest_clear_entered)
    hooks.on("app.cQuestResult", "enter", on_quest_result_enter)
end

return Ending
