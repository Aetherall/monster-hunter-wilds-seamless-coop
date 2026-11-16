-- The game's notify windows (ace.cGUINotifyWindowInfo): read as they are
-- requested, and answered without being opened, as the choice a player
-- makes (WindowEndExecuteFunc with that index), from inside the next frame.

local tasks = require("seamless_coop.base.tasks")

---@class sq.Window
---@field id integer
---@field choices integer
---@field cancellable boolean
---@field private finish REManagedObject?   its WindowEndExecuteFunc
local Window = {}
Window.__index = Window

---@param info REManagedObject?
---@return sq.Window?
function Window.read(info)
    if info == nil or info:get_type_definition():get_full_name() ~= "app.cGUINotifyWindowInfoApp" then return nil end
    local list = info:get_field("<ChoisesTextInfo>k__BackingField")
    ---@type sq.Window
    local self = setmetatable({}, Window)
    self.id = info:get_field("<NotifyWindowId>k__BackingField")
    self.choices = list and list:call("get_Count") or 0
    self.cancellable = info:get_field("<WindowCancelConditionFunc>k__BackingField") ~= nil
    self.finish = info:get_field("<WindowEndExecuteFunc>k__BackingField")
    return self
end

-- A message with one way out.
---@return boolean
function Window:plain() return self.choices <= 1 and not self.cancellable end

---@return string
function Window:describe()
    return string.format("window %d: %d choices, end func %s, cancel condition %s", self.id, self.choices, self.finish ~= nil,
        self.cancellable)
end

---@param choice integer
function Window:answer(choice)
    local finish = self.finish
    if finish == nil then return end
    finish:add_ref()
    tasks.spawn("answer window " .. self.id, function()
        finish:call("Invoke(System.Int32)", choice)
        finish:release()
    end)
end

return Window
