-- A guest out of the host's quest, in the host's world. It may join the
-- quest again. Once the host's quest is over, the host's field is entered
-- again.

local journal = require("seamless_coop.base.journal")
local Once = require("seamless_coop.base.once")
local State = require("seamless_coop.state")
local Entering = require("seamless_coop.ops.entering")
local Session = require("seamless_coop.game.session")
local Place = require("seamless_coop.place")
local Quest = require("seamless_coop.game.quest")
local note = journal.note

local HOST_BACK_SECONDS = 2

---@class sq.Outside: sq.State
local Outside = setmetatable({}, { __index = State })
Outside.__index = Outside

-- From the host's quest we joined, once out of it, or from a join of it
-- again that did not come.
---@param from sq.JoinedQuest|sq.Departing
---@return boolean entered
function Outside.from(from)
    ---@type sq.Outside
    local self = setmetatable({}, Outside)
    self.kind = "outside"
    return self:enter(from)
end

-- Waiting only makes sense in the link and out of a quest.
---@private
function Outside:check_still_waiting()
    if not Session.linked() then self:stop("the link ended while waiting for the host") end
    if Quest.current() ~= nil then self:stop("back in a quest while waiting for the host") end
end

---@param status sq.JoinStatus?
---@return sq.Once?
local function entry_time(status)
    if Place.Host.of(nil, status):idle() then return Once.at(os.clock() + HOST_BACK_SECONDS) end
    return nil
end

---@async
function Outside:run()
    ---@type sq.Once?
    local enter
    for _ in self:frames() do
        self:check_still_waiting()
        local status = Session.host_status()
        enter = enter or entry_time(status)
        if enter ~= nil and enter:due() then
            note("leave", "host back in the link (status %s): its field taken again", status)
            Entering.from(self)
            return
        end
    end
end

return Outside
