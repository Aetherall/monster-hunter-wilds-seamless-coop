local managers = require("seamless_coop.game.managers")

local Network = {}

---@return REManagedObject
function Network.manager() return managers.single("app.NetworkManager") end
---@return REManagedObject
function Network.service() return Network.manager():get_field("_SessionService") end
---@return REManagedObject
function Network.quest_session() return Network.service():get_field("_QuestSession") end
---@return REManagedObject
function Network.users() return Network.manager():get_field("_UserInfoManager") end
---@return REManagedObject
function Network.party() return Network.manager():get_field("_Party") end
---@return REManagedObject
function Network.requests() return Network.manager():get_field("_RequestManager") end

---@param g REManagedObject
---@return string
function Network.guid(g) return tostring(g:call("ToString()")) end

function Network.empty_guid() return ValueType.new(sdk.find_type_definition("System.Guid")) end

return Network
