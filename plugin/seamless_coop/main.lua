-- Seamless Coop: reads the world once per frame, lets the policy react
-- to it and runs the states, all from inside the game's frame.
--
--   base/        journal, settings, hooks, tasks, what outlives a reload
--   game/        the game's objects as classes of ours, one per file, and
--                the facts read off them
--   world        the situation we are in (with place, invitation,
--                party_quest)
--   state        the one thing the plugin is doing
--   policy       what to do in each situation
--   reactions    the game's events -> policy -> a state
--   frame        every frame: the world -> policy -> a state
--   ops/         one file per state (entering, leaving, departing,
--                hosted_quest, joined_quest, outside, travelling), the
--                ways a quest is started, the load made in place, the
--                shaping of a quest's end, the party's tasks
--   offer(s)     the offer on the feed's Y, and which one stands
--   words        what the player reads
--   ui           the REFramework menu entry

local journal = require("seamless_coop.base.journal")
local hooks = require("seamless_coop.base.hooks")
local tasks = require("seamless_coop.base.tasks")
local settings = require("seamless_coop.base.settings")
local Facts = require("seamless_coop.game.facts")
local LinkParty = require("seamless_coop.game.link_party")
local Quest = require("seamless_coop.game.quest")
local World = require("seamless_coop.world")
local State = require("seamless_coop.state")
local Taking = require("seamless_coop.ops.taking")
local HostedQuest = require("seamless_coop.ops.hosted_quest")
local Ending = require("seamless_coop.ops.ending")
local Offer = require("seamless_coop.offer")
local Reactions = require("seamless_coop.reactions")
local Frame = require("seamless_coop.frame")
local UI = require("seamless_coop.ui")

local M = {}

-- cGameSceneTransition.update(), every frame, inside the game's frame.
local function on_frame()
    journal.begin_frame()
    local facts = Facts.read()
    if facts ~= nil then
        local world = World.observe(facts, settings.values.enabled)
        State.guard(world)
        Offer.update()
        Frame.react(world)
    end
    tasks.run()
end

---@return string
local function switch_line()
    if settings.values.enabled then return "on" end
    return "off"
end

---@return string
local function world_line()
    local world = World.now()
    if world == nil then return "no world yet" end
    return world:describe()
end

---@return string
local function last_line()
    local last = State.last()
    if last == nil then return "" end
    return "; before: " .. last
end

---@return string
function M.status()
    return string.format("%s | %s | %s%s", switch_line(), world_line(), State.now():describe(), last_line())
end

-- The first version of the plugin, when it runs in this game: its hooks
-- can't be shared.
---@return boolean
local function earlier_version_runs()
    local old = rawget(_G, "seamless_quests_state")
    return type(old) == "table" and type(old.hooked) == "table" and next(old.hooked) ~= nil
end

function M.start()
    if earlier_version_runs() then
        return "an earlier version of Seamless Quests runs in this game: restart the game to load this one"
    end
    settings.load()
    hooks.forget()
    hooks.on("app.cGameSceneTransition", "update()", on_frame)
    LinkParty.install()
    Quest.install()
    Taking.install()
    HostedQuest.install()
    Ending.install()
    Offer.install()
    Reactions.install()
    UI.install(M.status)
    journal.note("load", "started: %s", M.status())
    return M.status()
end

-- For a running game: drops the modules so edited files load. The hooks
-- stay and call the new code.
function M.reload()
    for name in pairs(package.loaded) do
        if name:match("^seamless_coop%.") then package.loaded[name] = nil end
    end
    return require("seamless_coop.main").start()
end

return M
