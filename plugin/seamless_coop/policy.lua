-- What the plugin does, for each thing that happens in each situation. One
-- function per event; each takes the world (world.lua), the state we are
-- in when it matters (state.lua) and the event's own facts. No game calls.
--
-- A question with two answers is answered true or false, with why when
-- worth journaling. One with more is answered by calling one of the
-- answers the asker brings (`on`): the asker must bring them all, so a
-- decision added here does not check until every asker handles it.
-- `game` always means: left to the game.
--
-- The hooks and the frame (reactions.lua) ask here and carry the answer
-- out; the states (ops/) know how, never whether.

---@class sq.Policy
local Policy = {}

-- app.WarpDef.SITUATION_TYPE of cGameJumper.requestSceneJump: a travel by
-- the map, and the guest's jump home when the host ended the link.
---@enum sq.JumpSituation
local JumpSituation = { TRAVEL = 53, LINK_ENDED = 0x30 }

-- ChatDef.LOG_ID of the game's own notice of an environment invite.
local LOG_ENVIRONMENT_INVITE = 30

---@class sq.BoardPost
---@field stage integer
---@field director_busy boolean

---@class sq.CounterPostAnswers
---@field game fun(why: string?): sdk.PreHookResult?
---@field travel fun(free: sq.Free): sdk.PreHookResult?       the quest is in another stage: the party is told, we travel there and start it in place
---@field already fun(stage: integer): sdk.PreHookResult?     a quest is going on in that stage: not posted, the offer to join it made again
---@field start_here fun(free: sq.Free): sdk.PreHookResult?   the counter skips its "disband the link?" question and its new session; the departure is made in place
---@field ask_host fun(): sdk.PreHookResult?     the post becomes a request to the session's host

---@param w sq.World
---@return boolean
local function in_session(w) return not w:solo() end

---@param now sq.Now
---@param on sq.CounterPostAnswers
---@return sdk.PreHookResult?
local function host_post(now, on)
    local free = now:free()
    if free == nil then return on.game("we are " .. now:describe()) end
    return on.start_here(free)
end

-- A board quest for another stage: the poster goes there on its own and
-- starts it in place, so that the quest ends in place too and everyone
-- stays in its stage. Only in a link party: alone, the game's own start
-- is kept.
---@param w sq.World
---@param now sq.Now
---@param board sq.BoardPost
---@param on sq.CounterPostAnswers
---@return sdk.PreHookResult?
local function post_elsewhere(w, now, board, on)
    if not w:in_party() then
        return on.game(string.format("the quest is in stage %s, we are in %s, in no link party", board.stage, w.stage))
    end
    local free = now:free()
    if free == nil then return on.game("we are " .. now:describe()) end
    return on.travel(free)
end

---@param w sq.World
---@param now sq.Now
---@param board sq.BoardPost
---@param on sq.CounterPostAnswers
---@return sdk.PreHookResult?
local function post_here(w, now, board, on)
    if not in_session(w) then return on.game() end
    if w:hosting() then return host_post(now, on) end
    if board.director_busy then return on.game() end
    if w:host_in_quest() then return on.already(board.stage) end
    return on.ask_host()
end

-- One quest per stage: members may be in different quests at the same
-- time when those are in different stages. A post for a stage where a
-- member's quest goes on is answered by the offer to join that one.
---@param w sq.World
---@param now sq.Now
---@param board sq.BoardPost
---@param on sq.CounterPostAnswers
---@return sdk.PreHookResult?
function Policy.counter_post(w, now, board, on)
    if w:quest_in(board.stage) ~= nil then return on.already(board.stage) end
    if w:other_stage(board.stage) then return post_elsewhere(w, now, board, on) end
    return post_here(w, now, board, on)
end

-- Why we are not the one we asked the start as; nil when we are.
---@param w sq.World
---@param role sq.Role
---@return string?
local function wrong_role(w, role)
    if role == "guest" and w:hosting() then return "we host the quest session" end
    if role == "host" and not w:hosting() then return "we do not host the quest session" end
    return nil
end

-- The hunter's departure for a quest the plugin asked to start, which
-- requests the scene jump: made in place or not. role: the one we asked
-- as.
---@param w sq.World
---@param role sq.Role
---@param quest_stage integer?
---@return boolean in_place, string? why
function Policy.departure(w, role, quest_stage)
    local wrong = wrong_role(w, role)
    if wrong ~= nil then return false, wrong end
    if quest_stage == nil then return false, "no quest data" end
    if w:other_stage(quest_stage) then
        return false, string.format("quest in stage %s, we are in %s", quest_stage, w.stage)
    end
    return true
end

---@class sq.QuestStartedAnswers
---@field game fun()
---@field keep_limit fun()       only the member limit kept at the session's
---@field invite_others fun()    also: a member that starts a quest itself (a field hunt) invites the link's members, as only the host may; confirmed half a second later (member_invite)

-- The director's goQuest. joining: the game's flag; by_plugin: our own
-- late join is making the call.
---@param w sq.World
---@param joining boolean
---@param by_plugin boolean
---@param on sq.QuestStartedAnswers
function Policy.quest_started(w, joining, by_plugin, on)
    if not in_session(w) then return on.game() end
    if joining or by_plugin or w:hosting() then return on.keep_limit() end
    return on.invite_others()
end

-- A member that started a quest itself invites the others, unless what it
-- did was join the host's quest by the game's own accept (an invite from
-- another stage), which is no start of ours.
---@param w sq.World
---@return boolean invite, string? why
function Policy.member_invite(w)
    if w:host_playing() then return false, "the host's quest joined" end
    return true
end

-- Another member's quest invite, which the game is about to turn into a
-- notice.
---@class sq.QuestInvite
---@field stage integer              the stage the quest is played in
---@field director_busy boolean
---@field from_host fun(): boolean   asked in a host's world only

---@class sq.QuestInviteAnswers
---@field game fun(why: string?): sdk.PreHookResult?
---@field start_for_member fun(free: sq.Free): sdk.PreHookResult?   we host: a member asks for that quest
---@field follow_host fun(): sdk.PreHookResult?        we are a guest: joined once the host plays it
---@field hear fun(): sdk.PreHookResult?               a quest we are not with: remembered, and offered on Y instead of the game's notice

-- A quest in our stage and in our world is everyone's at once, without a
-- Y. Any other costs a travel or a world to enter: it is offered.
---@param w sq.World
---@param now sq.Now
---@param invite sq.QuestInvite
---@param on sq.QuestInviteAnswers
---@return sdk.PreHookResult?
function Policy.quest_invite(w, now, invite, on)
    if w:other_stage(invite.stage) then return on.hear() end
    return w.place:match({
        solo = on.hear,
        open = on.hear,
        joining = on.hear,
        host = function()
            if invite.director_busy then return on.game() end
            local free = now:free()
            if free == nil then return on.game() end
            return on.start_for_member(free)
        end,
        guest = function()
            local invited = w:invitation()
            local following = invited ~= nil and not invited:was_joined()
            if following or not invite.from_host() then return on.game() end
            return on.follow_host()
        end,
    })
end

---@class sq.FollowAnswers
---@field wait fun()
---@field forget fun(invited: sq.Invitation)   the host never started it
---@field join fun(invited: sq.Invitation, free: sq.Free)     the host has been playing it for a moment: joined in place

---@param w sq.World
---@return sq.Invitation?
local function awaited(w)
    local invited = w:invitation()
    if invited == nil or invited:was_joined() then return nil end
    return invited
end

---@param w sq.World
---@param invited sq.Invitation
---@return boolean
local function ready_to_join(w, invited)
    return invited:played_for_a_moment(w.at) and w:host_playing()
end

---@param w sq.World
---@param now sq.Now
---@param on sq.FollowAnswers
function Policy.follow(w, now, on)
    local invited = awaited(w)
    if invited == nil then return on.wait() end
    if invited:expired(w.at) then return on.forget(invited) end
    if not ready_to_join(w, invited) then return on.wait() end
    local free = now:free()
    if free == nil then return on.wait() end
    return on.join(invited, free)
end

---@param w sq.World
---@return boolean
local function outside_a_played_quest(w)
    return w:host_playing()
end

-- A guest out of the host's quest, in the host's world, may join that
-- quest again, by the counter's "Link Member Quests" or on Y: the quest
-- to join, nil when it may not.
---@param w sq.World
---@param now sq.Now
---@return sq.Invitation?, sq.Outside?
function Policy.rejoinable(w, now)
    local invited = w:invitation()
    if invited == nil or not invited:was_joined() then return nil end
    if not outside_a_played_quest(w) then return nil end
    local outside = now:outside()
    if outside == nil then return nil end
    return invited, outside
end

-- The quest of the host we stand with, which we were told of before we
-- were in its world: to be followed as if the host had invited us here.
---@param w sq.World
---@return sq.PartyQuest?
function Policy.host_quest_heard(w)
    local host = w.place:host()
    if host == nil or not host:playing() or w:invitation() ~= nil then return nil end
    return w:quest_of(host.id)
end

-- The hunter's action after a link leave, which requests the leave's
-- load: true when we stay where we are instead.
---@param w sq.World
---@param now sq.Now
---@return sq.Free?
function Policy.stays_after_link(w, now)
    if not w:guest_leaving() then return nil end
    return now:free()
end

---@param w sq.World
---@return boolean
local function may_enter(w)
    return not w.questing and not w.place:is("host")
end

-- The hunter's action after an Environment Link accept, which commits to
-- the join's load: true when the world is entered in place instead.
---@param w sq.World
---@param now sq.Now
---@param invite_stage integer?
---@return sq.Free? free, string? why
function Policy.enters_in_place(w, now, invite_stage)
    if not may_enter(w) then return nil end
    local free = now:free()
    if free == nil then return nil end
    if w:other_stage(invite_stage) then return nil, "link accepted from another stage" end
    return free
end

---@class sq.SceneJumpAnswers
---@field game fun(why: string?): sdk.PreHookResult?
---@field prepare_session fun(): sdk.PreHookResult?   a travel: the jump goes on, and the session we will invite the party to is made during its load
---@field stay fun(free: sq.Free): sdk.PreHookResult?              the jump home after the host ended the link

---@param w sq.World
---@param situation integer
---@return boolean
local function jump_home(w, situation)
    return situation == JumpSituation.LINK_ENDED and w:guest_leaving()
end

---@param w sq.World
---@param now sq.Now
---@param stage integer
---@param situation integer
---@param on sq.SceneJumpAnswers
---@return sdk.PreHookResult?
function Policy.scene_jump(w, now, stage, situation, on)
    if situation == JumpSituation.TRAVEL then return on.prepare_session() end
    if not jump_home(w, situation) then return on.game() end
    local free = now:free()
    if free == nil then return on.game() end
    if w:other_stage(stage) then
        return on.game(string.format("link ended, home is stage %s and we are in %s", stage, w.stage))
    end
    return on.stay(free)
end

---@param w sq.World
---@return boolean
local function party_at_rest(w) return w:in_party() and not w.questing end

---@param w sq.World
---@return boolean
local function alone_at_rest(w) return w:alone() and not w.questing end

---@param w sq.World
---@return boolean
function Policy.prepare_session(w) return party_at_rest(w) end

---@param w sq.World
---@return boolean
local function may_invite(w) return alone_at_rest(w) and w:in_party() end

---@param w sq.World
---@return boolean
function Policy.invite_after_travel(w) return may_invite(w) end

---@class sq.NeighbourAnswers
---@field met fun(member: sq.Member)   the party is invited to our world (they do the same; the first to press Y joins the other)
---@field nobody fun()                 nobody of the party is near
---@field unknown fun()                we can't tell, or can't act now

-- Where the other members are, as we see it, can be trusted: not during
-- a load, nor just after a travel or a return to our own world.
---@param w sq.World
---@return boolean
local function sees_members(w) return w.settled and w.stage >= 0 and w.playable and not w.loading end

---@param w sq.World
---@param on sq.NeighbourAnswers
function Policy.neighbour(w, on)
    if not may_invite(w) or not sees_members(w) then return on.unknown() end
    local near = w:members("near")()
    if near == nil then return on.nobody() end
    return on.met(near)
end

-- The game's own notice of an environment invite, which carries a Y prompt
-- of its own: hidden where our offer stands for the invite.
---@param w sq.World
---@param log integer
---@return boolean
function Policy.hides_game_notice(w, log) return log == LOG_ENVIRONMENT_INVITE and w:alone() end

-- The game's windows about an Environment Link: not opened, answered as
-- the choice a player makes.
--   348 "Leave Environment Link?" (a travel or a leave while linked): Yes
--   43  the link disbanded by its host, on its members: OK
--   283 after the leave (host): OK, only when a plain message
---@type table<integer, integer>
local WINDOW_ANSWERS = { [348] = 0, [43] = 0, [283] = 0 }
---@type table<integer, boolean>
local PLAIN_ONLY = { [283] = true }

---@param window sq.Window
---@return integer? answer, string? why
function Policy.window(window)
    local answer = WINDOW_ANSWERS[window.id]
    if answer == nil then return nil end
    if PLAIN_ONLY[window.id] and not window:plain() then return nil, "left to the game" end
    return answer
end

---@param w sq.World
---@return boolean
function Policy.can_accept(w) return alone_at_rest(w) end

---@class sq.OfferAnswers
---@field rejoin fun(host: sq.Host, invited: sq.Invitation, outside: sq.Outside)
---@field party_quest fun(quest: sq.PartyQuest, free: sq.Free)
---@field follow fun(invite: sq.Invite)

---@param w sq.World
---@param now sq.Now
---@param on sq.OfferAnswers
local function rejoin_offer(w, now, on)
    local host = w.place:host()
    if host == nil then return end
    local invited, outside = Policy.rejoinable(w, now)
    if invited ~= nil and outside ~= nil then on.rejoin(host, invited, outside) end
end

---@param w sq.World
---@param now sq.Now
---@param on sq.OfferAnswers
local function add_party_quest_offers(w, now, on)
    local free = now:free()
    if free == nil or w.questing then return end
    for quest in w:quests_elsewhere() do on.party_quest(quest, free) end
end

-- Not for a member whose quest is offered: that offer accepts the invite.
---@param w sq.World
---@param on sq.OfferAnswers
local function add_follow_offers(w, on)
    if not Policy.can_accept(w) then return end
    for invite in w:standing_invites() do
        if w:quest_of(invite.from) == nil then on.follow(invite) end
    end
end

-- In order of preference.
---@param w sq.World
---@param now sq.Now
---@param on sq.OfferAnswers
function Policy.offers(w, now, on)
    if not w.enabled then return end
    rejoin_offer(w, now, on)
    add_party_quest_offers(w, now, on)
    add_follow_offers(w, on)
end

-- Decided on 2026-11-16 and written without a run (the parts above that
-- say so): one quest per stage; a post for another stage is a travel and
-- a start in place; a member's quest we are not with is offered on Y,
-- which travels and joins; a post where a quest goes on is answered by
-- that offer.
--
-- Not covered:
--   an investigation posted for another stage (left to the game)
--   a member's quest already going on when we link with them: we only
--     know the quests we were sent an invite for
--   a post for another stage outside a link party (the game's own start
--     and return load)

return Policy
