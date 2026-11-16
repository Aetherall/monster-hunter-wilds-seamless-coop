-- Tasks: coroutines resumed once per frame from inside the game's frame,
-- where calls that make the game allocate are safe.

local memory = require("seamless_coop.base.memory")
local journal = require("seamless_coop.base.journal")

---@class sq.Task
---@field name string
---@field co thread
---@field wake number?

---@class sq.Tasks.Kept
---@field list sq.Task[]
---@type sq.Tasks.Kept
local kept = memory.keep("tasks", { list = {} })

local Tasks = {}

local NEXT = {}

---@param name string
---@param fn async fun()
function Tasks.spawn(name, fn)
    kept.list[#kept.list + 1] = { name = name, co = coroutine.create(fn) }
end

---@async
---@param seconds number
function Tasks.sleep(seconds) coroutine.yield(os.clock() + seconds) end

---@async
function Tasks.next_frame() coroutine.yield(NEXT) end

-- One step of `task`; false once it is over. A task that yields a time
-- sleeps until then.
---@param task sq.Task
---@return boolean alive
local function step(task)
    local ok, result = coroutine.resume(task.co)
    if not ok then
        journal.note("error", "task %s: %s", task.name, result)
        return false
    end
    task.wake = nil
    if type(result) == "number" then task.wake = result end
    return coroutine.status(task.co) ~= "dead"
end

function Tasks.run()
    local i, task = 1, kept.list[1]
    while task ~= nil do
        local asleep = task.wake ~= nil and os.clock() < task.wake
        if asleep or step(task) then
            i = i + 1
        else
            table.remove(kept.list, i)
        end
        task = kept.list[i]
    end
end

return Tasks
