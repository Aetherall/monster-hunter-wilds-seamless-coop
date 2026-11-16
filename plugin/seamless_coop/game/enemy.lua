local journal = require("seamless_coop.base.journal")
local managers = require("seamless_coop.game.managers")
local Elements = require("seamless_coop.game.elements")
local single = managers.single

-- EnemyDef.SYNC_TYPE.
local ONLY_LOCAL = 2

local function manager() return single("app.EnemyManager") end

-- An enemy of the field (app.cEnemyManageInfo, its context and its
-- character).
---@class sq.Enemy
---@field private info REManagedObject
---@field private context REManagedObject
---@field private em REManagedObject
local Enemy = {}
Enemy.__index = Enemy

---@param info REManagedObject?
---@return sq.Enemy?
function Enemy.wrap(info)
    local context = info and info:get_field("<Context>k__BackingField")
    local em = context and context:get_field("_Em")
    if not em then return nil end
    ---@type sq.Enemy
    local self = setmetatable({}, Enemy)
    self.info, self.context, self.em = info, context, em
    return self
end

---@return fun(): sq.Enemy?
function Enemy.all()
    local list = manager():get_field("_AllEnemyList")
    local array, count = list:get_field("_Array"), list:get_field("_Count")
    return Elements.each(count, function(i) return Enemy.wrap(array:get_element(i)) end)
end

---@param index integer
---@return sq.Enemy?
function Enemy.find(index)
    local by_index = manager():get_field("_EnemyListByUniqueIndex")
    if not by_index:call("ContainsKey", index) then return nil end
    return Enemy.wrap(by_index:call("get_Item", index))
end

---@return integer
function Enemy:index() return self.em:call("get_UniqueIndex") end

---@return string
function Enemy:label()
    return string.format("%s#%s", self.em:get_field("Basic"):get_field("EmID"), self:index())
end

---@return boolean
function Enemy:has_body() return self.info:get_field("<Object>k__BackingField") ~= nil end

---@param host integer
---@return boolean
function Enemy:is_replica_of(host)
    local net = self.em:get_field("NetInfo")
    return net ~= nil and net:get_field("_HostMemberIndex") == host and net:get_field("_SelfMemberIndex") ~= host
end

-- Never synced: a local animal.
---@return boolean
function Enemy:is_local()
    local net = self.em:get_field("NetInfo")
    return net == nil or net:get_field("_HostMemberIndex") == -1
end

-- Created by a PopEnemy event of the field schedule (the large monsters
-- and their packs): it carries the event's unique index.
---@return boolean
function Enemy:from_schedule() return self.em:get_field("ExSpawnUniqueIndex") ~= -1 end

-- The game's own handle on it, as a hook's return value.
---@return lightuserdata
function Enemy:pointer() return sdk.to_ptr(self.info) end

-- What a replica does when its host's removal arrives
-- (cEmRemoveAction.receivePacket): a local removal, no packet.
function Enemy:remove()
    local enemies = manager()
    local ok, err = pcall(enemies.call, enemies,
        "requestRemove(app.cEnemyContextHolder, app.EnemyDef.SYNC_TYPE, System.Boolean)", self.context, ONLY_LOCAL, false)
    if not ok then journal.note("error", "requestRemove(%s): %s", self:label(), err) end
end

---@param host integer
---@param pick fun(index: integer): boolean
---@return sq.Enemy[]
function Enemy.replicas(host, pick)
    ---@type sq.Enemy[]
    local found = {}
    for enemy in Enemy.all() do
        if enemy:is_replica_of(host) and pick(enemy:index()) then found[#found + 1] = enemy end
    end
    return found
end

-- Of two enemies with the same unique index: the one to keep, which is
-- the one that has a body, and the extra copy.
---@param first sq.Enemy
---@param second sq.Enemy
---@return sq.Enemy keep, sq.Enemy extra
local function pick(first, second)
    if second:has_body() and not first:has_body() then return second, first end
    return first, second
end

---@param kept table<integer, sq.Enemy>
---@param extras sq.Enemy[]
---@param enemy sq.Enemy
local function sort_out(kept, extras, enemy)
    local index = enemy:index()
    local first = kept[index]
    if first == nil then
        kept[index] = enemy
        return
    end
    kept[index], extras[#extras + 1] = pick(first, enemy)
end

-- A quest's start populates the field's local animals; made in place it
-- does so over the ones already here: the same unique index twice, never
-- synced. The extra copies, keeping the one that has a body.
---@return sq.Enemy[]
function Enemy.duplicates()
    ---@type table<integer, sq.Enemy>, sq.Enemy[]
    local kept, extras = {}, {}
    for enemy in Enemy.all() do
        if enemy:is_local() then sort_out(kept, extras, enemy) end
    end
    return extras
end

---@return sq.Enemy[]
function Enemy.of_schedule()
    ---@type sq.Enemy[]
    local found = {}
    for enemy in Enemy.all() do
        if enemy:from_schedule() then found[#found + 1] = enemy end
    end
    return found
end

---@param found sq.Enemy[]
---@return string
function Enemy.labels(found)
    local out = {}
    for i, enemy in ipairs(found) do out[i] = enemy:label() end
    return table.concat(out, " ")
end

---@param found sq.Enemy[]
function Enemy.remove_all(found)
    for _, enemy in ipairs(found) do enemy:remove() end
end

-- The game's host-migration step: the enemies of the field converted to
-- replicas of the member `host`.
---@param host integer
---@param session sq.SessionType
function Enemy.change_host(session, host)
    manager():call("evNetHostChange(app.net_session_manager.SESSION_TYPE, System.Int32)", session, host)
end

-- EnemyManager's layout change in progress, 0 when none.
---@return integer
function Enemy.layout_change_flow() return manager():call("get_CurrentLayoutChangeFlow()") end

-- A load's scene-load-end for the enemies. MissionManager.evSceneLoadEnd:
-- the running mission's enemy tag, then a CLEAR_ALL layout change, which
-- replaces every enemy in place. With an investigation on the director
-- only the layout change: the tag is then read from the quest data of the
-- game's table, which an investigation has not, without a null test (crash
-- 2026-11-15 16:46); its monsters come from its schedule.
---@return string how
function Enemy.scene_load_end()
    local missions = single("app.MissionManager")
    local quest = missions:get_field("_QuestDirector"):get_field("_QuestData")
    if quest == nil or quest:get_field("_QuestData") ~= nil then
        missions:call("evSceneLoadEnd()")
        return "evSceneLoadEnd"
    end
    manager():call(
        "requestChangeLayout(app.EnemyDef.LAYOUT_CHANGE_TYPE, app.FieldDef.STAGE, app.EnemyDef.LAYOUT_CHANGE_OPTION)", 1, -1, 0)
    return "layout change only (investigation)"
end

return Enemy
