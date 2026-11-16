---@class sq.Arg
local Arg = {}

---@param value lightuserdata?
---@return integer
function Arg.int(value) return sdk.to_int64(value) & 0xffffffff end

---@param value lightuserdata?
---@return boolean
function Arg.bool(value) return (sdk.to_int64(value) & 0xff) ~= 0 end

---@param value lightuserdata?
---@return REManagedObject?
function Arg.object(value) return sdk.to_managed_object(value) end

-- A boolean to return from a post handler.
---@param value boolean
---@return lightuserdata
function Arg.answer(value) return sdk.to_ptr(value and 1 or 0) end

return Arg
