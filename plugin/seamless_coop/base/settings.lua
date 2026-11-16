local memory = require("seamless_coop.base.memory")

local FILE = "seamless_coop.json"

---@class sq.Config
---@field enabled boolean          quests inside an Environment Link stay in it
---@field skip_free_time boolean   development: no free time after a clear

---@class sq.Settings.Kept
---@field values sq.Config
---@field loaded boolean
---@type sq.Settings.Kept
local kept = memory.keep("settings", { values = { enabled = true, skip_free_time = false }, loaded = false })

local Settings = { values = kept.values }

function Settings.load()
    if kept.loaded then return end
    kept.loaded = true
    local saved = json.load_file(FILE)
    if type(saved) ~= "table" then return end
    for key in pairs(kept.values) do
        if type(saved[key]) == "boolean" then kept.values[key] = saved[key] end
    end
end

function Settings.save() json.dump_file(FILE, kept.values) end

return Settings
