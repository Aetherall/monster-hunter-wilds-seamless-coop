local hooks = require("seamless_coop.base.hooks")
local arg = require("seamless_coop.base.arg")
local Missions = require("seamless_coop.game.missions")
local Session = require("seamless_coop.game.session")

-- app.MissionTypeList.TYPE of a field quest (a hunt started in the field).
local FIELD_QUEST = 5

-- The quest invite being received, for the time of the game's call.
---@type REManagedObject?
local invite_packet

-- A quest as it is played (app.cActiveQuestData).
---@class sq.Quest
---@field package data REManagedObject
local Quest = {}
Quest.__index = Quest

---@private
---@param data REManagedObject
---@return sq.Quest
function Quest.new(data)
    ---@type sq.Quest
    local self = setmetatable({}, Quest)
    self.data = data
    return self
end

---@param data REManagedObject?
---@return sq.Quest?
function Quest.wrap(data)
    if data == nil then return nil end
    return Quest.new(data)
end

---@return sq.Quest?
function Quest.current() return Quest.wrap(Missions.director():get_field("_QuestData")) end

-- Board quests the game's quest table knows are started by their mission
-- alone. An investigation is not one of them.
---@param mission integer
---@return boolean
function Quest.in_table(mission) return Missions.table_entry(mission) ~= nil end

---@param mission integer
---@return sq.Quest
function Quest.of_table(mission)
    local entry = Missions.table_entry(mission)
    if entry == nil then error("no quest data for mission " .. tostring(mission)) end
    local data = sdk.create_instance("app.cActiveQuestData", true):add_ref()
    data:call(".ctor(app.user_data.QuestData, System.Boolean)", entry, false)
    return Quest.new(data)
end

-- The stage of a quest of the game's table (user_data.QuestData
-- .getStage; read in a game on 2026-11-16: missions 136, 102, 110 are in
-- stages 0, 1, 2).
---@param mission integer
---@return integer
function Quest.table_stage(mission)
    local entry = Missions.table_entry(mission)
    if entry == nil then error("no quest data for mission " .. tostring(mission)) end
    return entry:call("getStage()")
end

-- An investigation (a saved quest) has no quest data in the game's table:
-- the quest travels in the invite. The game rebuilds it from the packet
-- for field quests only (Net_Party.recvInvitePartyQuest); the same two
-- calls here, on the packet being received. A quest rebuilt this way has
-- no save slot: starting it uses nobody's attempt on this game.
---@param mission integer
---@return sq.Quest?
function Quest.from_invite(mission)
    local packet = invite_packet
    if packet == nil or packet:get_field("QuestId") ~= mission then return nil end
    local keep = Session.keep_quest_of(packet)
    if keep == nil then return nil end
    local data = sdk.create_instance("app.cActiveQuestData", true):add_ref()
    data:call(".ctor(app.cKeepQuestData)", keep)
    return Quest.new(data)
end

-- What tells this quest from another: its data's address.
---@return integer
function Quest:key() return self.data:get_address() end
---@return integer
function Quest:mission() return self.data:get_field("_MissionId") end
---@return integer
function Quest:type() return self.data:get_field("_MissionType") end
---@return boolean
function Quest:is_field_quest() return self:type() == FIELD_QUEST end
---@return integer
function Quest:stage() return self.data:call("getStage") end

---@return string
function Quest:describe()
    local keep = self.data:get_field("_KeepQuestData")
    return string.format("mission %s type %s stage %s, %s targets, save slot %s", self:mission(), self:type(),
        keep:get_field("_StageType"), keep:get_field("_TargetEmNum"), keep:get_field("_Index"))
end

---@return REManagedObject
function Quest:raw() return self.data end

function Quest.install()
    hooks.on("app.Net_Party", "recvInvitePartyQuest(app.net_session_manager.SESSION_TYPE, System.Int32, app.net_packet.cSysQuestInvite)",
        function(args) invite_packet = arg.object(args[5]) end,
        function() invite_packet = nil end)
end

return Quest
