-- What the plugin is doing: exactly one thing at a time, in one slot.
--
--   free        nothing of ours in progress
--   entering    a member's world entered in place
--   leaving     a member's world left in place: our own field coming back
--   departing   a quest start the plugin asked for is on its way to the
--               hunter's departure
--   hosted      a quest we host, started in place, until our field is back
--   joined      the host's quest, joined in place, until our field is back
--               or we are out of it in the host's world
--   outside     a guest out of the host's quest, in the host's world,
--               until the host's quest is over
--   travelling  on our way to the stage of a quest, then to what we came
--               for: starting it, or joining its host
--
-- Each state is an object of a class of its own (ops/), whose `run` is a
-- task run one step per frame inside the game's frame (it waits with
-- self:frame() and self:sleep(), which do not come back once the state is
-- left). It owns everything the plugin knows about what it is doing:
-- when the state is left, by its end, by the next state or because the
-- world stopped matching it (`holds`), that knowledge is gone with it.
--
-- A state is entered from another one, handed over as a value: which
-- states lead to which is in the type of each class's `from`. Two
-- transitions of the field can't run at once, and a quest's ending can't
-- outlive its quest.
--
--   free ──> entering ──> free
--   free ──> leaving ──> free
--   free ──> departing ──> hosted ──> free
--                    └───> joined ──> free
--                            └─────> outside ──> entering
--                                       └──────> departing
--   free ──> travelling ──> departing        (a quest posted for another stage)
--                    └────> free             (a member's quest: its world is
--                                             then entered, its quest joined)
--
-- The state we are in is not handed out as a state (State.now() answers
-- a `sq.Now`): what depends on it is asked with `match`, which wants an
-- answer for every state, or with `when`, for the states named only, and
-- each answer is given the state as what it is.

local journal = require("seamless_coop.base.journal")
local tasks = require("seamless_coop.base.tasks")
local memory = require("seamless_coop.base.memory")
local note = journal.note

---@alias sq.StateKind "free"|"entering"|"leaving"|"departing"|"hosted"|"joined"|"outside"|"travelling"

---@class sq.State
---@field kind sq.StateKind
---@field protected left string?   why it was left, once it is
local State = {}
State.__index = State

---@class sq.Free: sq.State
local Free = setmetatable({}, { __index = State })
Free.__index = Free

-- An answer for every state.
---@class sq.StateCases
---@field free fun(state: sq.Free): any
---@field entering fun(state: sq.Entering): any
---@field leaving fun(state: sq.Leaving): any
---@field departing fun(state: sq.Departing): any
---@field hosted fun(state: sq.HostedQuest): any
---@field joined fun(state: sq.JoinedQuest): any
---@field outside fun(state: sq.Outside): any
---@field travelling fun(state: sq.Travelling): any

-- An answer for some states.
---@class sq.StateWhen
---@field free (fun(state: sq.Free): any)?
---@field entering (fun(state: sq.Entering): any)?
---@field leaving (fun(state: sq.Leaving): any)?
---@field departing (fun(state: sq.Departing): any)?
---@field hosted (fun(state: sq.HostedQuest): any)?
---@field joined (fun(state: sq.JoinedQuest): any)?
---@field outside (fun(state: sq.Outside): any)?
---@field travelling (fun(state: sq.Travelling): any)?

---@class sq.State.Kept
---@field doing sq.State?
---@field last string?     how the last state ended
---@type sq.State.Kept
local kept = memory.keep("state", {})

---@class sq.Now
---@field is fun(self: sq.Now, kind: sq.StateKind): boolean
---@field match fun(self: sq.Now, cases: sq.StateCases): any          the answer of the state's case
---@field when fun(self: sq.Now, cases: sq.StateWhen): any            the answer of the state's case; nil when it has none
---@field free fun(self: sq.Now): sq.Free?                            the state, when we are free
---@field outside fun(self: sq.Now): sq.Outside?                      the state, when we wait outside the host's quest
---@field describe fun(self: sq.Now): string                          for the status line

---@type sq.Free
local FREE = setmetatable({}, Free)
FREE.kind = "free"
local STOP = {}

---@return sq.State
local function current() return kept.doing or FREE end

---@return sq.Now
function State.now()
    ---@type any
    local now = current()
    return now
end

---@return string?
function State.last() return kept.last end

---@param kind sq.StateKind
---@return boolean
function State:is(kind) return self.kind == kind end

---@private
---@param cases sq.StateCases
---@return any
function State:match(cases)
    ---@type fun(state: sq.State): any
    local case = cases[self.kind]
    return case(self)
end

---@private
---@param cases sq.StateWhen
---@return any
function State:when(cases)
    ---@type (fun(state: sq.State): any)?
    local case = cases[self.kind]
    if case ~= nil then return case(self) end
    return nil
end

-- For a state that could not be entered from the one we are in: the
-- event is the game's.
---@param kind sq.StateKind
---@return boolean entered   false
function State.refused(kind)
    journal.later("state", "%s not entered from %s", kind, current().kind)
    return false
end

-- The state itself, when we are free: what the states that start from
-- free are entered from.
---@private
---@return sq.Free?
function State:free() return self:when({ free = function(state) return state end }) end

---@private
---@return sq.Outside?
function State:outside() return self:when({ outside = function(state) return state end }) end

---@return string
function State:describe() return self.kind end

-- Once per frame, before the tasks run: a state the world no longer
-- matches is left.
---@param world sq.World
function State.guard(world)
    local now = current()
    if now.left then return end
    local ok, why = now:holds(world)
    if not ok then now:leave(why or "its situation is gone") end
end

-- For each class to define.
---@async
function State:run() end

-- False and why when the world no longer matches the state.
---@param _world sq.World
---@return boolean holds, string? why
function State:holds(_world) return true end

-- Enters this state and runs it, from the state that leads to it; false
-- when that one is no longer the state we are in.
---@protected
---@param from sq.State
---@return boolean
function State:enter(from)
    if current() ~= from or from.left then return State.refused(self.kind) end
    if from ~= FREE then from.left = "left for " .. self.kind end
    kept.doing = self
    journal.later("state", "%s -> %s", from.kind, self.kind)
    tasks.spawn("state " .. self.kind, function() self:conclude(pcall(self.run, self)) end)
    return true
end

---@param result any
---@return string
local function reason_of(result)
    if type(result) == "table" and result[STOP] then return tostring(result.reason) end
    return "error: " .. tostring(result)
end

---@private
---@param ok boolean
---@param result any
function State:conclude(ok, result)
    if kept.doing == self then kept.doing = nil end
    kept.last = self.kind .. " done"
    if not ok then kept.last = self.kind .. " stopped: " .. reason_of(result) end
    note("state", "%s", kept.last)
end

-- Leaves this state, for nothing: its task stops at its next frame.
---@param why string
function State:leave(why)
    if self == FREE then return end
    self.left = why
    if kept.doing == self then kept.doing = nil end
    journal.later("state", "%s left: %s", self.kind, why)
end

---@async
function State:frame()
    tasks.next_frame()
    if self.left then self:stop(self.left) end
end

---@async
---@param seconds number
function State:sleep(seconds)
    local wake = os.clock() + seconds
    repeat self:frame() until os.clock() >= wake
end

---@async
---@param seconds number
---@param done fun(): boolean
---@return boolean
function State:wait_until(seconds, done)
    local deadline = os.clock() + seconds
    while not done() do
        if os.clock() >= deadline then return false end
        self:frame()
    end
    return true
end

-- One turn per frame, counted from 1, inside `run`:
--   for poll in self:frames() do ... break when done ... end
---@return async fun(): integer
function State:frames()
    local n = 0
    ---@async
    local function turn()
        if n > 0 then self:frame() end
        n = n + 1
        return n
    end
    return turn
end

---@param reason string
---@return never
function State:stop(reason) error({ [STOP] = true, reason = reason, kind = self.kind }, 0) end

return State
