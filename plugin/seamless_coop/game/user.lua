local Network = require("seamless_coop.game.network")

-- Net_QuestUserInfo.QuestJoinStatus: where a user is with a quest.
---@enum sq.JoinStatus
local JoinStatus = { COMPLETE = 9, START = 10, RESULT = 11 }

-- A user of a session (app.Net_UserInfo).
---@class sq.User
---@field private info REManagedObject
local User = {}
User.__index = User

---@param info REManagedObject?
---@return sq.User?
function User.wrap(info)
    if info == nil then return nil end
    ---@type sq.User
    local self = setmetatable({}, User)
    self.info = info
    return self
end

---@private
---@return REManagedObject?
function User:param() return self.info:get_field("param") end

---@private
---@param name string
function User:of_param(name)
    local param = self:param()
    if param == nil then error("a user without its param") end
    return param:get_field(name)
end

---@return boolean
function User:valid() return self.info:get_field("<IsValid>k__BackingField") end
---@return boolean
function User:is_self() return self.info:get_field("<IsSelf>k__BackingField") end
---@return integer
function User:member_index() return self.info:get_field("<MemberIndex>k__BackingField") end
---@return sq.JoinStatus?
function User:status() return self.info:get_field("<Status>k__BackingField") end

---@return string?
function User:name()
    local param = self:param()
    return param and param:get_field("PlName")
end

---@return string
function User:id() return Network.guid(self:of_param("HunterId")) end

-- The same, nil for a user whose param is not there yet.
---@return string?
function User:known_id()
    local param = self:param()
    return param and Network.guid(param:get_field("HunterId"))
end

-- Net_UserParam.IsQuest. UNVERIFIED: that it is true for as long as the
-- user is in a quest, and that it reaches the members of the link party
-- who are in another session (the stage, FieldId, does).
---@return boolean
function User:questing() return self:of_param("IsQuest") end
---@return integer
function User:stage() return self:of_param("FieldId") end

User.JoinStatus = JoinStatus

return User
