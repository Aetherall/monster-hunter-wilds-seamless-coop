-- The game's screens (GUIManager._AllGUI), found by the name of their
-- type.

local managers = require("seamless_coop.game.managers")
local Elements = require("seamless_coop.game.elements")

local Screens = {}

---@param screen REManagedObject?
---@param name string
---@return boolean
local function is_named(screen, name) return screen ~= nil and screen:get_type_definition():get_name() == name end

---@param name string
---@return fun(): REManagedObject?
function Screens.named(name)
    local gui = managers.find("app.GUIManager")
    local all = gui and gui:get_field("_AllGUI")
    return Elements.each(all and all:get_size() or 0, function(i)
        local screen = all:get_element(i)
        if is_named(screen, name) then return screen end
        return nil
    end)
end

return Screens
