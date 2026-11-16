-- A quest's end that is ours to make in place: it exists once the quest
-- is armed, and holds everything known about that end. It only
-- remembers; what is done to the game with it is ops/ending.lua's.

-- How far an abandon's own showing was cut, in the order it happens.
---@enum sq.AbandonCut
local AbandonCut = {
    NONE = 0,
    RETIRE = 1,       -- the hunter's retire action skipped
    WAIT = 2,         -- the wait before the "quest abandoned" notice cut
    NOTICE = 3,       -- the notice ended by us
    NOTICE_END = 4,   -- the notice's own end refused
}

---@class sq.OwnEnd
---@field private jumps integer            return jumps answered false
---@field private kept_session boolean     an abandon's session leave was skipped
---@field private abandon sq.AbandonCut
---@field private free_time boolean        the free time after a clear was skipped
local OwnEnd = {}
OwnEnd.__index = OwnEnd
OwnEnd.Cut = AbandonCut

---@return sq.OwnEnd
function OwnEnd.new()
    ---@type sq.OwnEnd
    local self = setmetatable({}, OwnEnd)
    self.jumps, self.kept_session, self.abandon, self.free_time = 0, false, AbandonCut.NONE, false
    return self
end

function OwnEnd:count_jump() self.jumps = self.jumps + 1 end

---@return integer
function OwnEnd:jumps_cut() return self.jumps end

function OwnEnd:keep_session() self.kept_session = true end

---@return boolean
function OwnEnd:session_kept() return self.kept_session end

---@param step sq.AbandonCut
---@return boolean
function OwnEnd:has_cut(step) return self.abandon >= step end

-- The abandon's showing is cut this far now; it never goes back.
---@param step sq.AbandonCut
function OwnEnd:cut(step)
    if step > self.abandon then self.abandon = step end
end

function OwnEnd:skip_free_time() self.free_time = true end

---@return boolean
function OwnEnd:free_time_skipped() return self.free_time end

return OwnEnd
