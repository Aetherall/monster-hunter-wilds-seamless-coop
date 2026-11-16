-- What lasts one game call: raised for the scope of a to-be-closed
-- variable, around a call we make,
--   local _ <close> = flag:raise()
-- or raised by a hook's pre handler and lowered by its post handler.

---@class sq.Flag
---@field private up boolean
local Flag = {}
Flag.__index = Flag
Flag.__close = function(self) self.up = false end

---@return sq.Flag
function Flag.new()
    ---@type sq.Flag
    local self = setmetatable({}, Flag)
    self.up = false
    return self
end

---@return sq.Flag
function Flag:raise()
    self.up = true
    return self
end

function Flag:lower() self.up = false end

---@return boolean
function Flag:raised() return self.up end

return Flag
