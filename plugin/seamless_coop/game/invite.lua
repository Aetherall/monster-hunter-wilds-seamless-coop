local Network = require("seamless_coop.game.network")

-- An environment invite received (app.Net_Party.InvitedLinkParty). Each
-- one is a new object of the game: its address is its key.
---@class sq.Invite
---@field key integer
---@field from string       the inviter's hunter id
---@field name string
---@field stage integer
---@field private object REManagedObject
---@field private user REManagedObject
local Invite = {}
Invite.__index = Invite

---@param object REManagedObject?
---@return sq.Invite?
function Invite.wrap(object)
    local user = object and object:get_field("_User")
    if object == nil or user == nil then return nil end
    ---@type sq.Invite
    local self = setmetatable({}, Invite)
    self.object, self.user = object, user
    self.key = object:get_address()
    self.from = Network.guid(user:get_field("HunterId"))
    self.name = tostring(user:get_field("_HunterName"))
    self.stage = object:get_field("_Stage")
    return self
end

-- The invite's dialog answered yes, without the dialog and its
-- "connecting" window: the request alone, with no callback.
function Invite:accept()
    Network.requests():call(
        "acceptInviteLinkPartySync(System.Guid, System.Action`2<System.Boolean,app.NETWORK_ERROR_CODE>, System.String, System.Boolean)",
        self.user:get_field("HunterId"), nil, self.object:get_field("_Password"), false)
end

return Invite
