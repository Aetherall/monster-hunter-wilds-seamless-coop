local journal = require("seamless_coop.base.journal")
local managers = require("seamless_coop.game.managers")
local Screens = require("seamless_coop.game.screens")
local Quest = require("seamless_coop.game.quest")
local note = journal.note

-- GUIFlowGUI050001View.Flow.OrderHost states.
local ORDER_ACCEPT, ORDER_END = 4, 5
-- GUIDefApp.SHUTDOWN_TYPE.
local CLOSE_QUEST_COUNTER_MENU = 2

-- The quest counter, at the state where a quest is posted
-- (GUIFlowGUI050001View.Flow.OrderHost).
---@class sq.Counter
---@field private flow REManagedObject
local Counter = {}
Counter.__index = Counter

---@param order REManagedObject?
---@return sq.Counter?
function Counter.wrap(order)
    if order == nil then return nil end
    ---@type sq.Counter
    local self = setmetatable({}, Counter)
    self.flow = order
    return self
end

-- The counter's search for quest sessions is its "Link Member Quests"
-- (app.net_quest_session.cSearchQuestSessionInfo).
---@param search REManagedObject?
---@return boolean
function Counter.searches_link(search) return search ~= nil and search:get_field("<IsLink>k__BackingField") end

-- The quest being posted, nil when there is none; and, when it is a
-- board quest posted online, what the policy needs of it.
---@return sq.Quest? quest, sq.BoardPost? board
function Counter:posted()
    local param = self.flow:call("get_QuestOrderParam()")
    local quest = Quest.wrap(param and param:get_field("ActiveQuestData"))
    if quest == nil then return nil, nil end
    if not param:get_field("IsOnline") or quest:is_field_quest() then return quest, nil end
    ---@type sq.BoardPost
    local board = { stage = param:get_field("QuestViewData"):call("get_Stage()"), director_busy = Quest.current() ~= nil }
    return quest, board
end

-- The post (OrderHost: START asks "disband the link?" -> CREATE_SESSION ->
-- ACCEPT_QUEST) sent straight to ACCEPT_QUEST: no question, no session;
-- the game's own accept follows.
function Counter:accept()
    self.flow:call("setFacilityByeDialog()")
    self.flow:set_field("_State", ORDER_ACCEPT)
end

-- The counter ended as after the game's own accept (stateAccept and the
-- flow's acceptQuest, without the accept): its menus shut, the counter's
-- flow told the quest was accepted, this state terminated. A state merely
-- parked in END leaves the quest sheet up and the hunter held until the
-- quest starts.
function Counter:finish()
    local order = self.flow
    order:call("setFacilityByeDialog()")
    managers.single("app.GUIManager"):call("shutdownGUIWithType(app.GUIDefApp.SHUTDOWN_TYPE, ace.GUIDef.SHUTDOWN_MODE)", CLOSE_QUEST_COUNTER_MENU, 0)
    order:call("closeUI()")
    local ended, why = pcall(function()
        local state = order:get_field("_Core")
        local counter = state:get_field("Context"):get_field("OwnerFlowContxt")
        counter:set_field("<IsBackFlow>k__BackingField", false)
        counter:set_field("<IsAceept>k__BackingField", true)
        state:call("terminate(ace.cStateBase)", order)
    end)
    if not ended then
        order:set_field("_State", ORDER_END)
        note("error", "counter flow not terminated, parked instead: %s", why)
    end
end

---@param gui REManagedObject
local function end_flow(gui)
    local handle = gui:get_field("_QuestCounterFlowHandle")
    if handle ~= nil and not handle:call("get_IsEnd") then handle:call("terminate") end
end

-- The counter closed as one leaves it by hand, from any of its screens:
-- its menus shut, its screen asked to close, its flow ended, the
-- facility's talk ended.
function Counter.close()
    local gui = managers.single("app.GUIManager")
    gui:call("shutdownGUIWithType(app.GUIDefApp.SHUTDOWN_TYPE, ace.GUIDef.SHUTDOWN_MODE)", CLOSE_QUEST_COUNTER_MENU, 0)
    for screen in Screens.named("GUI050000") do
        pcall(screen.call, screen, "requestClose(System.Boolean)", false)
    end
    end_flow(gui)
    gui:call("stopFacilityEvent()")
end

return Counter
