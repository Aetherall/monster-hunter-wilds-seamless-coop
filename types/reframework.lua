---@meta
-- REFramework's Lua API, as far as the plugin uses it. What the game's
-- objects hold is not typed: fields and calls answer `any`.

---@class REManagedObject
local REManagedObject = {}
---@param method string
---@param ... any
---@return any
function REManagedObject:call(method, ...) end
---@param name string
---@return any
function REManagedObject:get_field(name) end
---@param name string
---@param value any
function REManagedObject:set_field(name, value) end
---@return integer
function REManagedObject:get_address() end
---@return RETypeDefinition
function REManagedObject:get_type_definition() end
---@return REManagedObject
function REManagedObject:add_ref() end
function REManagedObject:release() end
---@return integer
function REManagedObject:get_size() end
---@param index integer
---@return any
function REManagedObject:get_element(index) end
---@param offset integer
---@return integer
function REManagedObject:read_qword(offset) end
---@param offset integer
---@return integer
function REManagedObject:read_dword(offset) end

---@class RETypeDefinition
local RETypeDefinition = {}
---@return string
function RETypeDefinition:get_name() end
---@return string
function RETypeDefinition:get_full_name() end
---@param name string
---@return REMethodDefinition?
function RETypeDefinition:get_method(name) end
---@return REMethodDefinition[]
function RETypeDefinition:get_methods() end

---@class REMethodDefinition
local REMethodDefinition = {}
---@return string
function REMethodDefinition:get_name() end
---@return lightuserdata
function REMethodDefinition:get_function() end
---@param object any
---@param ... any
---@return any
function REMethodDefinition:call(object, ...) end

---@class ValueType
---@field new fun(type: RETypeDefinition?): REManagedObject
ValueType = {}

---@alias HookArgs lightuserdata[]

---@class sdk
sdk = {}
---@enum sdk.PreHookResult
sdk.PreHookResult = { CALL_ORIGINAL = 0, SKIP_ORIGINAL = 1 }
---@param name string
---@return RETypeDefinition?
function sdk.find_type_definition(name) end
---@param name string
---@return REManagedObject?
function sdk.get_managed_singleton(name) end
---@param name string
---@param simplify boolean?
---@return REManagedObject
function sdk.create_instance(name, simplify) end
---@param method REMethodDefinition
---@param pre (fun(args: HookArgs): sdk.PreHookResult?)?
---@param post (fun(retval: lightuserdata): lightuserdata?)?
function sdk.hook(method, pre, post) end
---@param value any
---@return integer
function sdk.to_int64(value) end
---@param value any
---@return REManagedObject?
function sdk.to_managed_object(value) end
---@param value any
---@return lightuserdata
function sdk.to_ptr(value) end
---@param value any
---@param type string
---@return REManagedObject?
function sdk.to_valuetype(value, type) end

---@class re
re = {}
---@param fn fun()
function re.on_draw_ui(fn) end

---@class imgui
imgui = {}
---@param label string
---@return boolean
function imgui.tree_node(label) end
function imgui.tree_pop() end
---@param text string
function imgui.text(text) end
---@param label string
---@param value boolean
---@return boolean changed, boolean value
function imgui.checkbox(label, value) end

---@class json
json = {}
---@param path string
---@return any
function json.load_file(path) end
---@param path string
---@param value any
function json.dump_file(path, value) end
