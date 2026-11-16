local Words = {}

---@type table<integer, string>
local STAGES = { [0] = "the Windward Plains", "the Scarlet Forest", "the Oilwell Basin", "the Iceshard Cliffs", "the Ruins of Wyveria" }

---@param stage integer
---@return string
function Words.stage(stage) return STAGES[stage] or ("stage " .. tostring(stage)) end

---@param host sq.Host
---@return string, string
function Words.rejoin(host)
    return (host.name or "The host") .. " is still in the quest", "Rejoin the quest"
end

---@param invite sq.Invite
---@param our_stage integer
---@return string, string
function Words.invite(invite, our_stage)
    if invite.stage == our_stage then return invite.name .. " is here", "Join " .. invite.name end
    return invite.name .. " traveled to " .. Words.stage(invite.stage), "Join " .. invite.name
end

-- The quest's own name is not read yet.
---@param quest sq.PartyQuest
---@param our_stage integer
---@return string, string
function Words.party_quest(quest, our_stage)
    local prompt = "Join " .. (quest.name or "the quest")
    if quest.stage == our_stage then return "A quest is going on here", prompt end
    return "A quest is going on in " .. Words.stage(quest.stage), prompt
end

---@param stage integer
---@return string
function Words.already(stage) return "A quest is already going on in " .. Words.stage(stage) end

return Words
