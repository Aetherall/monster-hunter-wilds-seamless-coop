local memory = require("seamless_coop.base.memory")
local settings = require("seamless_coop.base.settings")

---@class sq.UI.Kept
---@field drawn boolean              the draw callback is registered, which can be done once per game run
---@field status (fun(): string)?    the status line of the modules loaded now
---@type sq.UI.Kept
local kept = memory.keep("ui", { drawn = false })

local UI = {}

---@param label string
---@param key "enabled"|"skip_free_time"
---@return boolean changed
local function checkbox(label, key)
    local changed, value = imgui.checkbox(label, settings.values[key])
    if changed then settings.values[key] = value end
    return changed
end

local function draw()
    if not imgui.tree_node("Seamless Coop") then return end
    local enabled = checkbox("Quests inside an Environment Link stay in it", "enabled")
    local skip = checkbox("Development: skip the free time after a clear", "skip_free_time")
    if enabled or skip then settings.save() end
    if kept.status then imgui.text(kept.status()) end
    imgui.tree_pop()
end

---@param status fun(): string
function UI.install(status)
    kept.status = status
    if kept.drawn then return end
    kept.drawn = true
    re.on_draw_ui(draw)
end

return UI
