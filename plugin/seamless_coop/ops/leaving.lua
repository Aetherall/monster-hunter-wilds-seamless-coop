-- A member's world left in place: a guest's leave of the link, or the
-- host's end of it. The game's leave has run but for its load; the field
-- we stand in becomes our own.

local State = require("seamless_coop.state")
local Load = require("seamless_coop.ops.load")

---@class sq.Leaving: sq.State
local Leaving = setmetatable({}, { __index = State })
Leaving.__index = Leaving

---@param from sq.Free
---@return boolean entered
function Leaving.from(from)
    ---@type sq.Leaving
    local self = setmetatable({}, Leaving)
    self.kind = "leaving"
    return self:enter(from)
end

---@async
function Leaving:run()
    local load = Load.out(self)
    load:session_left(true)
    load:drop_host_schedule()
    load:restore_field(false)
    Load.settle_home()
end

return Leaving
