local managers = require("seamless_coop.game.managers")

local Missions = {}

---@return REManagedObject
function Missions.manager() return managers.single("app.MissionManager") end
---@return REManagedObject
function Missions.director() return Missions.manager():get_field("_QuestDirector") end

---@return boolean
function Missions.questing() return Missions.manager():call("get_IsActiveQuest") end

---@param mission integer
---@return REManagedObject?
function Missions.table_entry(mission) return Missions.manager():call("getQuestData(app.MissionIDList.ID)", mission) end

return Missions
