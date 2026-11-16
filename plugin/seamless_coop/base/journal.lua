-- The journal: reframework/data/seamless_coop.log, one line per thing
-- the plugin did, flushed at every line.

local memory = require("seamless_coop.base.memory")

local FILE = "seamless_coop.log"

---@class sq.Line
---@field kind string
---@field text string

---@class sq.Journal.Kept
---@field frame integer
---@field later sq.Line[]
---@field file file?
---@type sq.Journal.Kept
local kept = memory.keep("journal", { frame = 0, later = {} })

local Journal = {}

---@param fmt string
---@param ... any
---@return string
local function format(fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    return ok and text or tostring(fmt)
end

-- Inside the game's frame only.
---@param kind string
---@param fmt string
---@param ... any
function Journal.note(kind, fmt, ...)
    if kept.file == nil then kept.file = io.open(FILE, "a") end
    if kept.file == nil then return end
    kept.file:write(string.format("%s %d %s %s\n", os.date("%Y-%m-%d %H:%M:%S"), kept.frame, kind, format(fmt, ...)))
    kept.file:flush()
end

-- A line from a hook, which may run on another thread than the frame's:
-- written at the next frame.
---@param kind string
---@param fmt string
---@param ... any
function Journal.later(kind, fmt, ...)
    kept.later[#kept.later + 1] = { kind = kind, text = format(fmt, ...) }
end

function Journal.begin_frame()
    kept.frame = kept.frame + 1
    if #kept.later == 0 then return end
    local lines = kept.later
    kept.later = {}
    for _, line in ipairs(lines) do Journal.note(line.kind, "%s", line.text) end
end

return Journal
