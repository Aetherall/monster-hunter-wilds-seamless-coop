-- The host's enemies taken as ours are joined to its session. It starts
-- with a late join and lasts until the next load into a world or a quest.

local hooks = require("seamless_coop.base.hooks")
local arg = require("seamless_coop.base.arg")
local memory = require("seamless_coop.base.memory")
local Enemy = require("seamless_coop.game.enemy")

-- A late join's account of the enemies the host names: the new ones, and
-- the ones already here that became the host's.
---@class sq.Taking
---@field host integer
---@field private taken integer
---@field private created integer
---@field private refused integer
---@field private named table<integer, boolean>
local Taking = {}
Taking.__index = Taking

---@class sq.Taking.Kept
---@field taking sq.Taking?
---@type sq.Taking.Kept
local account = memory.keep("taking", {})
-- The enemy the host is creating, for the time of the game's call.
---@type REManagedObject?
local create_packet

---@param host integer
---@return sq.Taking
function Taking.begin(host)
    ---@type sq.Taking
    local self = setmetatable({}, Taking)
    self.host, self.taken, self.created, self.refused, self.named = host, 0, 0, 0, {}
    account.taking = self
    return self
end

function Taking.forget() account.taking = nil end

---@param index integer
function Taking:new_enemy(index)
    self.created = self.created + 1
    self.named[index] = true
end

-- The host created an enemy whose unique index exists here: ours when it
-- is already a replica of the host, refused otherwise.
---@param index integer
---@return sq.Enemy?
function Taking:take(index)
    local enemy = Enemy.find(index)
    if enemy == nil or not enemy:is_replica_of(self.host) then
        self.refused = self.refused + 1
        return nil
    end
    self.taken = self.taken + 1
    self.named[index] = true
    return enemy
end

---@return boolean
function Taking:any() return self.created + self.taken > 0 end

---@return sq.Enemy[]
function Taking:unnamed() return Enemy.replicas(self.host, function(index) return not self.named[index] end) end

---@return string
function Taking:describe() return string.format("%d enemies new, %d taken, %d refused", self.created, self.taken, self.refused) end

-- EnemyManager.receivePacket_Create returns null for a unique index that
-- exists, which stops the enemy's late-join sync at its first phase and
-- leaves it without the host's health and state. Since a late join, a null
-- result for an enemy that is already a replica of the host becomes that
-- enemy.
---@param args HookArgs
local function on_enemy_create(args)
    create_packet = arg.object(args[2])
end

---@param retval lightuserdata
local function on_enemy_created(retval)
    local taking, packet = account.taking, create_packet
    create_packet = nil
    if taking == nil or packet == nil then return end
    local index = packet:read_dword(0x20)
    if sdk.to_int64(retval) ~= 0 then
        taking:new_enemy(index)
        return
    end
    local enemy = taking:take(index)
    if enemy ~= nil then return enemy:pointer() end
end

function Taking.install()
    hooks.on("app.EnemyManager", "receivePacket_Create(app.net_packet.cEmCreate)", on_enemy_create, on_enemy_created)
end

return Taking
