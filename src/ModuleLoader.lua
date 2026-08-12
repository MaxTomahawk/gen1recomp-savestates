local ModuleLoader = {}
ModuleLoader.__index = ModuleLoader

local function validPath(path)
  if type(path) ~= "string" or path == "" or path:sub(1, 1) == "/"
      or path:sub(-1) == "/" or path:find("\\", 1, true)
      or path:find("//", 1, true) or not path:match("^[%w_./-]+$") then
    return false
  end
  for segment in path:gmatch("[^/]+") do
    if segment == "." or segment == ".." then return false end
  end
  return true
end

function ModuleLoader.new(mod)
  assert(type(mod) == "table" and type(mod.read) == "function",
    "ModuleLoader.new needs a mod with mod:read")
  return setmetatable({ mod = mod, cache = {} }, ModuleLoader)
end

function ModuleLoader:load(path)
  if not validPath(path) then
    return nil, "invalid_module_path", "Invalid mod module path: " .. tostring(path)
  end
  if self.cache[path] ~= nil then return self.cache[path] end

  local readOk, source, readErr = pcall(self.mod.read, self.mod, path)
  if not readOk or type(source) ~= "string" then
    return nil, "module_missing",
      ("Could not read mod module %s: %s"):format(path,
        tostring(readOk and readErr or source))
  end

  local chunk, compileErr = load(source, "@" .. self.mod.path .. "/" .. path)
  if not chunk then
    return nil, "module_compile_failed",
      ("Could not compile mod module %s: %s"):format(path, tostring(compileErr))
  end

  local initOk, exported = pcall(chunk)
  if not initOk then
    return nil, "module_init_failed",
      ("Could not initialize mod module %s: %s"):format(path, tostring(exported))
  end
  if exported == nil then
    return nil, "module_init_failed",
      ("Mod module %s returned no export."):format(path)
  end

  self.cache[path] = exported
  return exported
end

return ModuleLoader
