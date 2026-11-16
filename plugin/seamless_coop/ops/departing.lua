-- A quest start the plugin asked for is on its way to the hunter's
-- departure, which is then ours to make in place (ops/quest_start.lua).
-- If the departure does not come in time, the start was the game's after
-- all.

local journal = require("seamless_coop.base.journal")
local State = require("seamless_coop.state")
local Outside = require("seamless_coop.ops.outside")
local note = journal.note

-- How long a start we asked for may take to reach the hunter's departure.
local PENDING_SECONDS = 30

---@class sq.Departing: sq.State
---@field role sq.Role            the one we asked as
---@field mission integer
---@field private ask (async fun(state: sq.Departing))?   what asks the game for the start, in the task
---@field private back_outside boolean    from `outside`: back there if the departure does not come
local Departing = setmetatable({}, { __index = State })
Departing.__index = Departing

-- `ask` asks the game for the start, inside the state's task; nil when
-- the game was asked already.
---@param from sq.Free|sq.Outside|sq.Travelling
---@param role sq.Role
---@param mission integer
---@param ask (async fun(state: sq.Departing))?
---@return boolean entered
function Departing.from(from, role, mission, ask)
    ---@type sq.Departing
    local self = setmetatable({}, Departing)
    self.kind, self.role, self.mission, self.ask = "departing", role, mission, ask
    self.back_outside = from:is("outside")
    return self:enter(from)
end

---@param role sq.Role
---@return sq.Departing?
function Departing.pending(role)
    return State.now():when({ departing = function(departing) return departing.role == role and departing or nil end })
end

---@async
function Departing:run()
    local ok, err = pcall(function()
        if self.ask then self.ask(self) end
        self:sleep(PENDING_SECONDS)
    end)
    if self.left then self:stop(self.left) end
    if not ok then note("error", "mission %d not started: %s", self.mission, err) end
    if self.back_outside then Outside.from(self) end
end

function Departing:give_up() self:leave("its departure is the game's") end

return Departing
