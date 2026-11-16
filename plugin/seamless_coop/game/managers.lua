local Managers = {}

-- A manager of the game, nil before the game has made it.
---@param name string
---@return REManagedObject?
function Managers.find(name) return sdk.get_managed_singleton(name) end

---@param ... string
---@return boolean
function Managers.exist(...)
    for _, name in ipairs({ ... }) do
        if sdk.get_managed_singleton(name) == nil then return false end
    end
    return true
end

---@param name string
---@return REManagedObject
function Managers.single(name)
    local object = sdk.get_managed_singleton(name)
    if object == nil then error("no " .. name, 2) end
    return object
end

---@param type_name string
---@param method_name string
---@return REMethodDefinition
function Managers.method(type_name, method_name)
    local td = sdk.find_type_definition(type_name)
    local method = td and td:get_method(method_name)
    if method == nil then error("no method " .. type_name .. "." .. method_name, 2) end
    return method
end

return Managers
