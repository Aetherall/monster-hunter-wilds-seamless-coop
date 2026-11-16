local managers = require("seamless_coop.game.managers")

local Scene = {}

---@return REManagedObject
local function flow() return managers.single("app.GameFlowManager") end

---@return boolean
function Scene.playable() return flow():call("get_IsPlayableScene") end

---@return boolean
function Scene.loading() return flow():call("get_Loading") end

return Scene
