local managers = require("seamless_coop.game.managers")
local Network = require("seamless_coop.game.network")
local User = require("seamless_coop.game.user")
local Elements = require("seamless_coop.game.elements")

-- app.net_session_manager.SESSION_TYPE.
---@enum sq.SessionType
local SessionType = { QUEST = 2, LINK = 3 }

-- Net_SessionService.SESSION_SEQUENCE_TYPE.
local SEQUENCE_QUEST = 1

---@class sq.Session
local Session = {}

-- In an Environment Link: to the game, any quest session with link sync.
---@return boolean
function Session.linked() return managers.single("app.EnvironmentManager"):get_field("_IsLinkPartySync") end
---@return boolean
function Session.hosting() return Network.service():call("isSessionHost", SessionType.QUEST, false) end
---@return boolean
function Session.multiplay() return Network.service():call("isMultiplay(app.net_session_manager.SESSION_TYPE)", SessionType.QUEST) end

---@return sq.User?
function Session.host()
    return User.wrap(Network.users():call("getHostUserInfo(app.net_session_manager.SESSION_TYPE)", SessionType.QUEST))
end

---@return sq.JoinStatus?
function Session.host_status()
    local host = Session.host()
    return host and host:status()
end

---@return integer
function Session.host_index()
    return Network.service():call("getHostIndex(app.net_session_manager.SESSION_TYPE, System.Boolean)", SessionType.QUEST, true)
end

-- Our own session is online once we are a valid user of it.
---@return boolean
function Session.online()
    local self = User.wrap(Network.users():call("getSelfUserInfo(app.net_session_manager.SESSION_TYPE, System.Boolean)",
        SessionType.QUEST, true))
    return self ~= nil and self:valid()
end

---@param kind sq.SessionType
---@return integer
function Session.size(kind) return Network.users():call("getMemberNum(app.net_session_manager.SESSION_TYPE)", kind) end

---@param kind sq.SessionType
---@return fun(): sq.User?
function Session.users(kind)
    local list = Network.users():call("getUserInfoList(app.net_session_manager.SESSION_TYPE)", kind)
    local array = list and list:get_field("_ListInfo")
    return Elements.each(array and array:get_size() or 0, function(i)
        local user = User.wrap(array:get_element(i))
        if user ~= nil and user:valid() then return user end
        return nil
    end)
end

-- The session's own member limit, 0 when it has none.
---@return integer
function Session.member_limit()
    local info = Network.quest_session():get_field("_SessionInfo")
    local param = info and info:get_field("Param")
    return param and param:get_field("<MaxJoinNum>k__BackingField") or 0
end

-- The session the menu's "invite" makes (cGUINetworkRequest
-- .reqLinkPartySyncInvite), without its window. The requests' callbacks
-- are optional (NetworkRequestManager.move tests them).
function Session.create()
    local info = sdk.create_instance("app.net_quest_session.cCreateQuestSessionInfo", true):add_ref()
    info:call("init()")
    info:set_field("<MaxJoinNum>k__BackingField", 4)
    info:set_field("<QuestNo>k__BackingField", -1)
    Network.requests():call(
        "createSession(app.net_session_manager.SESSION_TYPE, app.net_session_manager.cCreateSessionInfo, System.Action`2<System.Boolean,app.NETWORK_ERROR_CODE>)",
        SessionType.QUEST, info, nil)
end

-- The session told we wait for its sync. Inside a link's session it takes
-- its link branch and puts the sequence back to the link's.
---@return any done
function Session.notify_wait_sync() return Network.quest_session():call("notityWaitSync(System.Boolean)", true) end

---@return boolean changed
function Session.resume_quest_sequence()
    local s = Network.service()
    if s:get_field("_CurrentSequenceSessionType") == SEQUENCE_QUEST then return false end
    s:call("setCurrentSequenceSessionType(app.Net_SessionService.SESSION_SEQUENCE_TYPE)", SEQUENCE_QUEST)
    return true
end

-- The method the host's LoadAfter waiter is, when goQuest registered it.
---@return REMethodDefinition
function Session.join_sync_method()
    return managers.method("app.net_quest_session.cQuestSession", "waitCompleteJoinSync(System.Boolean)")
end

-- The host's wait for the members who depart with it; true once done.
---@param first boolean
---@return boolean
function Session.join_sync_done(first) return Network.quest_session():call("waitCompleteJoinSync(System.Boolean)", first) == true end

---@param first boolean
---@return boolean
function Session.late_join_done(first) return Network.quest_session():call("waitComplateLateJoin(System.Boolean)", first) == true end

-- The session's part of a member's late departure for the host's quest.
function Session.go_quest_late()
    Network.quest_session():call("goQuest(System.Boolean, System.Boolean, System.Byte, System.Boolean)", true, true, 0, false)
end

---@param packet REManagedObject
---@return REManagedObject?
function Session.keep_quest_of(packet)
    return Network.service():call("convertPacketToKeepQuestData(app.net_packet.cSysKeepQuestData)", packet)
end

Session.Type = SessionType

return Session
