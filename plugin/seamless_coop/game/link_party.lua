local journal = require("seamless_coop.base.journal")
local hooks = require("seamless_coop.base.hooks")
local arg = require("seamless_coop.base.arg")
local Flag = require("seamless_coop.base.flag")
local Network = require("seamless_coop.game.network")
local Invite = require("seamless_coop.game.invite")
local Elements = require("seamless_coop.game.elements")
local note = journal.note

-- Raised while a member sends the invite only a host may send.
local forging = Flag.new()

---@class sq.LinkParty
local LinkParty = {}

---@return fun(): sq.Invite?
function LinkParty.invites()
    local invited = Network.party():get_field("_InvitedSyncList")
    local array, count = invited:get_field("_Array"), invited:call("get_Count")
    return Elements.each(count, function(i) return Invite.wrap(array:get_element(i)) end)
end

-- The whole party (empty Guid) invited to our environment in `stage`.
---@param stage integer
function LinkParty.invite(stage)
    Network.requests():call("inviteLinkPartySync(System.Guid, app.FieldDef.STAGE, System.Action`2<System.Boolean,app.NETWORK_ERROR_CODE>)",
        Network.empty_guid(), stage, nil)
end

---@return boolean
function LinkParty.joining() return Network.party():get_field("_IsJoiningSync") end

---@return integer?
function LinkParty.accepted_stage()
    local invite = Network.party():get_field("_AcceptInviteInfo")
    return invite and invite:get_field("_Stage")
end

---@return REMethodDefinition
local function quest_invite_method()
    ---@type REMethodDefinition?
    local method
    for _, candidate in ipairs(Network.party():get_type_definition():get_methods()) do
        if candidate:get_name():find("inviteLinkPartyQuest", 1, true) then method = candidate end
    end
    if method == nil then error("no Net_Party.inviteLinkPartyQuest") end
    return method
end

-- The game only lets the quest session's host invite the link's members
-- to its quest (INet_LinkParty.inviteLinkPartyQuest tests isSessionHost).
-- A member sends the same invite with that one test answered true, only
-- during the call.
function LinkParty.invite_to_quest_as_member()
    local object, method = Network.party(), quest_invite_method()
    -- The game invites each member once per quest (Net_UserParam.IsQuestInvite):
    -- a request the host did not start must be repeatable.
    object:call("resetQuestInviteState()")
    local ok, result
    do
        local _ <close> = forging:raise()
        ok, result = pcall(method.call, method, object)
    end
    note("quest", "invite sent as a member: %s", tostring(ok and result))
end

local function on_is_session_host()
    if forging:raised() then return arg.answer(true) end
end

function LinkParty.install()
    hooks.on("app.Net_SessionService", "isSessionHost(app.net_session_manager.SESSION_TYPE, System.Boolean)", nil, on_is_session_host)
end

return LinkParty
