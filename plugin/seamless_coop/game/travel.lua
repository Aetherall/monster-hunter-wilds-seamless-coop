-- A travel to another stage by a call: the map's own last call once a
-- camp is chosen, without the map.
--
-- Seen alone, in no link (2026-11-16): the hunter departs, the stage
-- changes 3 s later and the hunter stands at the camp 8 s after the
-- call; no scene jump. UNVERIFIED in a link party and in an Environment
-- Link, where the game's own travel is a scene jump (situation 53): the
-- same call is expected to take that path by itself (the hunter's
-- departure picks it, PlayerCommonAction.cFastTravelGo.departure), and
-- to skip the map's "Leave Environment Link?" window, which the map asks
-- before this call.

local managers = require("seamless_coop.game.managers")

local Travel = {}

---@return REManagedObject
local function gui() return managers.single("app.GUIManager") end

-- The camp the map lists first for `stage` (cGUIMapController
-- .getFastTravelList, sorted as the map shows it); it answers with the
-- map closed and for a stage we are not in.
---@param stage integer
---@return REManagedObject?
local function first_camp(stage)
    local map = gui():get_field("<MAP3D>k__BackingField")
    local list = map and map:call("getFastTravelList(app.FieldDef.STAGE, System.Boolean)", stage, false)
    if list == nil or list:call("get_Count") == 0 then return nil end
    return list:call("get_Item", 0):get_field("ContextHolder")
end

-- Inside the game's frame. False when the stage has no camp to travel to
-- or we have no hunter. UNVERIFIED: what a hunter who cannot depart (in
-- an action, in a fight) does with the request; the caller waits for the
-- arrival and gives up after a while.
---@param stage integer
---@return boolean asked
function Travel.to(stage)
    local camp = first_camp(stage)
    if camp == nil then return false end
    return gui():get_field("_FastTravel"):call("travel(app.cGimmickContextHolder, System.Boolean)", camp, false)
end

-- From the call until the hunter stands at the camp and is played again
-- (MissionManager.isFastTravel; seen true from the call to 15 s after
-- it, alone). UNVERIFIED for a travel that is a scene jump: if it stays
-- true there, the arrival is never seen and the travel is given up.
---@return boolean
function Travel.under_way() return managers.single("app.MissionManager"):call("isFastTravel()") end

return Travel
