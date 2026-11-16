-- A quest we host, started in place: the explored field is swapped for
-- the quest's, the quest is played, and our own field comes back.

local journal = require("seamless_coop.base.journal")
local hooks = require("seamless_coop.base.hooks")
local arg = require("seamless_coop.base.arg")
local State = require("seamless_coop.state")
local InQuest = require("seamless_coop.ops.in_quest")
local Load = require("seamless_coop.ops.load")
local Director = require("seamless_coop.game.director")

-- The end is armed this long after the field is settled.
local ARM_SECONDS = 1
-- EnemyDef.LAYOUT_CHANGE_TYPE.
local TAKE_OVER = 0

---@class sq.HostedQuest: sq.InQuest
---@field private making_field boolean   the quest's start is still populating the field
local HostedQuest = setmetatable({}, { __index = InQuest })
HostedQuest.__index = HostedQuest

---@param from sq.Departing
---@param quest sq.Quest
---@return boolean entered
function HostedQuest.from(from, quest)
    ---@type sq.HostedQuest
    local self = setmetatable({}, HostedQuest)
    self.kind, self.making_field = "hosted", true
    self:begin(quest)
    return self:enter(from)
end

---@private
---@async
function HostedQuest:make_quest_field()
    local load = self.load
    load:settle()
    load:host_field()
    local deadline = load:notify(true)
    local request = load:host_sync(deadline)
    load:host_layout(request)
    Load.fade_in()
end

---@protected
function HostedQuest:settled()
    Load.remove_duplicates("join")
    self.making_field = false
end

---@private
---@async
---@param session_kept boolean
function HostedQuest:bring_field_back(session_kept)
    Load.out(self):restore_field(session_kept)
    Director.finish_end()
    Load.settle_home()
end

---@protected
---@param settled_at number
---@return number
function HostedQuest:arm_time(settled_at) return settled_at + ARM_SECONDS end

---@async
function HostedQuest:run()
    self:make_quest_field()
    self:play()
    local outcome = self:end_session()
    if outcome == "game" then return end
    self:bring_field_back(outcome == "kept")
end

-- The host's start makes the quest's field with its own CLEAR_ALL.
---@return boolean
function HostedQuest:makes_the_field() return self.making_field end

-- EnemyManager.requestChangeLayout: while the host's start runs in place,
-- the quest's mission asks for TAKE_OVER layout changes (its load, then
-- its start objective), which a load does not get; with the CLEAR_ALL
-- made here they created the target three times. Only the CLEAR_ALL is
-- let through, as in the load.
---@param args HookArgs
local function on_layout_request(args)
    local making = State.now():when({ hosted = function(quest) return quest:makes_the_field() end })
    if not making or arg.int(args[3]) ~= TAKE_OVER then return end
    journal.later("join", "host: requestChangeLayout(TAKE_OVER) skipped")
    return sdk.PreHookResult.SKIP_ORIGINAL
end

function HostedQuest.install()
    hooks.on("app.EnemyManager",
        "requestChangeLayout(app.EnemyDef.LAYOUT_CHANGE_TYPE, app.FieldDef.STAGE, app.EnemyDef.LAYOUT_CHANGE_OPTION)", on_layout_request)
end

return HostedQuest
