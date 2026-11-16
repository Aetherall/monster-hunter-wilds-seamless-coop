-- What must outlive a reload of the modules (main.reload): each module
-- that needs it asks for a table of its own, by name, and nobody else
-- can reach that table. Each name is claimed once per load.

---@type table<string, table>?
local found = rawget(_G, "seamless_coop")
---@type table<string, table>
local store = found or {}
rawset(_G, "seamless_coop", store)

---@type table<string, boolean>
local claimed = {}

local Memory = {}

---@generic T: table
---@param name string
---@param initial T
---@return T
function Memory.keep(name, initial)
    if claimed[name] then error("kept twice: " .. name, 2) end
    claimed[name] = true
    if store[name] == nil then store[name] = initial end
    ---@type any
    local kept = store[name]
    return kept
end

return Memory
