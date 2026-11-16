local journal = require("seamless_coop.base.journal")
local managers = require("seamless_coop.game.managers")
local note = journal.note

---@class sq.Hunter
local Hunter = {}

---@return REManagedObject
local function character() return managers.single("app.PlayerManager"):call("getMasterPlayer()"):call("get_Character()") end

-- An abandoned quest plays the hunter's retire action, which the return
-- load ends. No load here: back to the standing action.
function Hunter.release_retire_pose()
    local hunter = character()
    local controller = hunter:call("get_QuestActionController()")
    if not controller:get_field("_IsRetireWithAction") then return end
    controller:set_field("_IsRetireWithAction", false)
    local id = ValueType.new(sdk.find_type_definition("ace.ACTION_ID"))
    id:set_field("_Category", 0)
    id:set_field("_Index", 1)
    hunter:call("changeActionRequest(app.AppActionDef.LAYER, ace.ACTION_ID, System.Boolean)", 0, id, true)
    note("leave", "retire action ended")
end

-- The hunter's action after an Environment Link accept, as the accept
-- dialog's callback asks for it.
function Hunter.link_action()
    character():call("get_QuestActionController()"):call("requestLinkPartyAction(System.Boolean)", true)
end

return Hunter
