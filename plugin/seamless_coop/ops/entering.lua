-- A member's world entered in place: a guest enters the host's
-- Environment Link, or takes the host's field again after a quest. The
-- host's environment and field schedule, then the session's late join.

local State = require("seamless_coop.state")
local Load = require("seamless_coop.ops.load")

---@class sq.Entering: sq.State
---@field private load sq.Load
local Entering = setmetatable({}, { __index = State })
Entering.__index = Entering

---@param from sq.Free|sq.Outside
---@return boolean entered
function Entering.from(from)
    ---@type sq.Entering
    local self = setmetatable({}, Entering)
    self.kind = "entering"
    self.load = Load.into(self)
    return self:enter(from)
end

---@async
function Entering:run()
    local load = self.load
    load:environment("world")
    local deadline = load:notify(false)
    load:late_join(false, deadline)
    Load.fade_in()
end

return Entering
