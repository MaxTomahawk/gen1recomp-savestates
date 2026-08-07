local Test = dofile("tests/testlib.lua")
local T = Test.new("core composition")

local logs = {}
local mod = {
  id = "savestates",
  version = "0.1.0",
  path = "mods/savestates",
  exports = {},
  storage = {},
  checkpoints = {},
  options = {
    get = function() return nil end,
    define = function(self, schema) self.schema = schema return schema end,
  },
  log = {
    info = function(_, format, ...)
      logs[#logs + 1] = (format):format(...)
    end,
    error = function(_, format, ...)
      logs[#logs + 1] = "ERROR " .. (format):format(...)
    end,
  },
}
function mod:read(path)
  local file, err = io.open(path, "rb")
  if not file then return nil, err end
  local source = file:read("*a")
  file:close()
  return source
end

local entry = dofile("main.lua")
T:eq(type(entry), "function", "main returns a Gen1Recomp entry function")
local ok, err = pcall(entry, mod)
T:check(ok, "entry composes without throwing: " .. tostring(err))
T:eq(mod.exports.snapshotFormat, 1, "composition publishes snapshot format compatibility")
T:eq(mod.exports.apiVersion, 1, "composition publishes its inter-mod API version")
T:eq((mod.exports.supportedStateKinds or {})[1], "overworld",
  "composition accurately advertises only implemented runtime kinds")
T:eq(type(mod.exports.quickSave), "function", "composition publishes quicksave command")
T:eq(type(mod.exports.quickLoad), "function", "composition publishes quickload command")
T:eq(type(mod.exports.undoLastLoad), "function", "composition publishes undo command")
T:eq(#(mod.options.schema or {}), 9, "composition registers the full options schema")
T:check(type(logs[#logs]) == "string" and logs[#logs]:find("core ready", 1, true),
  "successful composition logs one ready lifecycle message")
for _, message in ipairs(logs) do
  T:check(not message:match("^ERROR"), "successful composition emits no error log")
end

T:finish()
