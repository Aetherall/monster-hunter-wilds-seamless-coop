-- The game's environment (app.EnvironmentManager): the stage we are in,
-- the field's role in a session (whose field schedule runs) and the
-- field's load flow, which a load drives and the plugin drives in place.

local managers = require("seamless_coop.game.managers")

-- EnvironmentManager.EX_LOAD_FLOW: where the field's load is.
---@enum sq.LoadFlow
local LoadFlow = { WAIT_OTHER = 2, LOADING = 3, COMPLETED = 6 }

-- EnvironmentManager.EX_SCENE_SETUP_TYPE: a guest of the host's explored
-- field.
local EXPLORE_JOIN = 8
-- EnvironmentManager.FIELD_DATA_LAYER: a link's or a quest's override.
local OVERRIDE_LAYER = 2

---@class sq.Environment
local Environment = { LoadFlow = LoadFlow }

local function manager() return managers.single("app.EnvironmentManager") end

-- The stage we are in; -1 during a load.
---@return integer
function Environment.stage() return manager():get_field("_CurrentStage") end

---@return integer
function Environment.role() return manager():get_field("<ExSceneSetupType>k__BackingField") end

---@param role integer
function Environment.set_role(role)
    manager():call("set_ExSceneSetupType(app.EnvironmentManager.EX_SCENE_SETUP_TYPE)", role)
end

-- A guest of the host's field schedule: the director imports it, follows
-- the host's events and stops running its own; saves skip it.
function Environment.become_explore_guest() Environment.set_role(EXPLORE_JOIN) end

-- The game's own choice of role, as a load makes it: from the quest, the
-- session and who hosts it. Answers the role before and after.
---@return integer before, integer after
function Environment.choose_role()
    local before = Environment.role()
    manager():call("setExSceneSetupType()")
    return before, Environment.role()
end

---@return boolean
function Environment.is_guest() return manager():call("get_IsExGuest") end

-- The explored field's schedule goes to the save.
function Environment.clean_up_field() manager():call("cleanUpExField()") end

-- The load's environment sync: asks the host for its forecast, time and
-- moon, and for its field schedule when our role is a guest's. True once
-- answered.
---@param first boolean
---@return boolean
function Environment.sync_done(first) return manager():call("sendRequestLoadBeforeSyncPacket(System.Boolean)", first) == true end

-- A load's scene-load-end: the field set up for its role (the explored
-- field's schedule back from the save and started, when it is ours).
function Environment.set_up_field() manager():call("setupExFieldFromLoadEnd()") end

---@param first boolean
---@return sq.LoadFlow
function Environment.update_field_load(first)
    manager():call("updateExFieldFromLoading(System.Boolean)", first)
    return Environment.load_flow()
end

---@return sq.LoadFlow
function Environment.load_flow() return manager():get_field("_ExLoadFlow") end

-- A host waits for its members' load-flow requests, which members that do
-- not load never send: past that wait by hand. False when it does not
-- wait.
---@return boolean skipped
function Environment.skip_wait_for_members()
    if Environment.load_flow() ~= LoadFlow.WAIT_OTHER then return false end
    manager():set_field("_ExLoadFlow", LoadFlow.WAIT_OTHER + 1)
    return true
end

-- A link's override layer is cleared by the next load
-- (EnvironmentManager.evSceneLoadBefore): the same call here. A quest's
-- host leaves its weather and time in that layer too.
function Environment.clear_override()
    local env = manager()
    local layer = env:get_field("_FieldEnvironmentData_Quest"):get_element(env:get_field("_CurrentStage"))
    if env:get_field("_NeedClearOverrideOfLinkPartySync") or not layer:get_field("_IsEmpty") then
        env:call("clearOverride(app.EnvironmentManager.FIELD_DATA_LAYER)", OVERRIDE_LAYER)
        env:set_field("_NeedClearOverrideOfLinkPartySync", false)
    end
end

return Environment
