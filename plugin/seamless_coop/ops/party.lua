-- The link party between worlds: our environment's session made and the
-- party invited to it, and an invite accepted, all without the game's
-- windows. The work is done in tasks, which last many frames: each asks
-- for the world as it is when it needs it.

local journal = require("seamless_coop.base.journal")
local tasks = require("seamless_coop.base.tasks")
local memory = require("seamless_coop.base.memory")
local policy = require("seamless_coop.policy")
local World = require("seamless_coop.world")
local Session = require("seamless_coop.game.session")
local LinkParty = require("seamless_coop.game.link_party")
local Hunter = require("seamless_coop.game.hunter")
local Feed = require("seamless_coop.game.feed")
local note = journal.note

---@class sq.Party.Kept
---@field session_requested_at number?   when our session was last asked for
---@field invited_to integer?            the stage the party was last invited to
---@type sq.Party.Kept
local kept = memory.keep("party", {})

---@class sq.Party
local Party = {}

local INVITE_SECONDS = 15
local ACCEPT_SECONDS = 20
local ARRIVAL_SECONDS = 60

---@async
---@param seconds number
---@param every number
---@param done fun(): boolean
---@return boolean
local function wait_until(seconds, every, done)
    local deadline = os.clock() + seconds
    while not done() do
        if os.clock() > deadline then return false end
        tasks.sleep(every)
    end
    return true
end

local function create_session()
    Session.create()
    kept.session_requested_at = os.clock()
end

---@async
---@return boolean
local function session_online()
    if Session.online() then return true end
    if os.clock() - (kept.session_requested_at or -100) > INVITE_SECONDS then create_session() end
    return wait_until(INVITE_SECONDS, 0.2, Session.online)
end

-- The link party invited to our environment in `stage`, as the menu's
-- "invite" does: our session created when it is not online, then the
-- invite.
---@async
---@param stage integer
---@return boolean invited
local function invite(stage)
    if not session_online() then
        note("party", "our environment's session not online after %d s: the party not invited", INVITE_SECONDS)
        return false
    end
    LinkParty.invite(stage)
    note("party", "the link party invited to our environment in stage %s", stage)
    return true
end

---@return boolean
local function arrived()
    local w = World.now()
    return w ~= nil and w.playable and not w.loading
end

---@async
---@param stage integer
local function invite_on_arrival(stage)
    tasks.sleep(0.5)
    wait_until(ARRIVAL_SECONDS, 0.5, arrived)
    tasks.sleep(1)
    local w = World.now()
    if w == nil or w.stage ~= stage or not w:alone() then return end
    invite(stage)
end

-- As a travel's scene jump is requested: our environment's session is
-- created during the travel's load, once the link's own is left, so that
-- the invite goes out on arrival.
---@async
local function prepare_session()
    local w = World.now()
    if w == nil or not policy.prepare_session(w) then return end
    if not wait_until(INVITE_SECONDS, 0.2, function() return not Session.online() end) then return end
    create_session()
    note("party", "our environment's session requested during the travel")
end

function Party.prepare_session() tasks.spawn("our session during the travel", prepare_session) end

---@param stage integer
function Party.invite_after_travel(stage)
    kept.invited_to = stage
    tasks.spawn("invite the party after a travel", function() invite_on_arrival(stage) end)
end

-- The party was already invited to `stage`: once is enough while its
-- members stay near.
---@param stage integer
---@return boolean
function Party.invited_to(stage) return kept.invited_to == stage end

---@async
---@param stage integer
---@return boolean invited
function Party.invite(stage)
    kept.invited_to = stage
    return invite(stage)
end

---@param stage integer
function Party.invite_here(stage)
    kept.invited_to = stage
    tasks.spawn("invite the party here", function() invite(stage) end)
end

-- Nobody of the party is near any more: the next one met is invited.
function Party.nobody_near() kept.invited_to = nil end

-- An environment invite accepted: the request, then on success the call
-- the dialog's callback makes, the hunter's link action. In our stage the
-- plugin turns that into entering the world in place; from another stage
-- the game loads into the inviter's.
---@async
---@param invitation sq.Invite
function Party.accept(invitation)
    local name = invitation.name
    if LinkParty.joining() then
        note("party", "%s's environment invite not accepted: already joining", name)
        return
    end
    invitation:accept()
    note("party", "%s's environment invite accepted without its dialog", name)
    Feed.say("Joining " .. name .. "...")
    if not wait_until(ACCEPT_SECONDS, 0.1, function() return Session.linked() and not Session.hosting() end) then
        note("party", "%s's environment: not joined after %d s", name, ACCEPT_SECONDS)
        return
    end
    note("party", "%s's environment joined: the hunter's link action", name)
    Hunter.link_action()
end

return Party
