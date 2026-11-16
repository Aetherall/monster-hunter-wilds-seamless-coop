-- The host, as seen from its quest that we joined: it tells when the
-- host, once seen in the quest, has been out of it for a moment (it
-- abandoned).

local Place = require("seamless_coop.place")

local OUT_SECONDS = 1.5

---@class sq.HostWatch
---@field private seen "never"|"in"|"gone"
---@field private out_at number?   when the host seen out is taken for out
local HostWatch = {}
HostWatch.__index = HostWatch

---@return sq.HostWatch
function HostWatch.new()
    ---@type sq.HostWatch
    local self = setmetatable({}, HostWatch)
    self.seen = "never"
    return self
end

---@private
---@return boolean
function HostWatch:out_for_a_moment()
    self.out_at = self.out_at or os.clock() + OUT_SECONDS
    return os.clock() >= self.out_at
end

---@param status sq.JoinStatus?
---@return boolean
function HostWatch:out(status)
    if self.seen == "gone" or status == nil then return false end
    if Place.Host.of(nil, status):in_quest() then
        self.seen, self.out_at = "in", nil
        return false
    end
    if self.seen == "never" then return false end
    return self:out_for_a_moment()
end

-- We acted on the host being out: nothing more to watch.
function HostWatch:done() self.seen = "gone" end

return HostWatch
