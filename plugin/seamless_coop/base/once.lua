-- Something to do once, when its time has come:
--   local arm = Once.at(os.clock() + 3)
--   ... every frame: if arm:due() then ... end

---@class sq.Once
---@field private time number?
local Once = {}
Once.__index = Once

---@param time number   as os.clock() tells it
---@return sq.Once
function Once.at(time)
    ---@type sq.Once
    local self = setmetatable({}, Once)
    self.time = time
    return self
end

-- True the first time it is asked at or after its time, false ever after.
---@return boolean
function Once:due()
    if self.time == nil or os.clock() < self.time then return false end
    self.time = nil
    return true
end

return Once
