-- The elements of one of the game's lists, as an iterator: those `at`
-- answers for, in order.
--   for user in Elements.each(size, function(i) return User.wrap(array:get_element(i)) end) do

local Elements = {}

---@generic T
---@param count integer
---@param at fun(index: integer): T?   the element at a 0-based index, nil to skip it
---@return fun(): T?
function Elements.each(count, at)
    local i = -1
    return function()
        while i + 1 < count do
            i = i + 1
            local element = at(i)
            if element ~= nil then return element end
        end
        return nil
    end
end

return Elements
