local Test = dofile("tests/testlib.lua")
local T = Test.new("module loader")
local ModuleLoader = dofile("src/ModuleLoader.lua")

local sources = {
  ["good.lua"] = "return { value = 42 }",
  ["bad-syntax.lua"] = "return {",
  ["throws.lua"] = "error('boom')",
}
local reads = {}
local mod = {
  path = "mods/savestates",
  read = function(_, path)
    reads[path] = (reads[path] or 0) + 1
    local source = sources[path]
    if not source then return nil, "no file" end
    return source
  end,
}

local loader = ModuleLoader.new(mod)
local escaped, escapedCode = loader:load("../other.lua")
T:eq(escaped, nil, "a traversal path has no export")
T:eq(escapedCode, "invalid_module_path", "module paths cannot escape the mod")
T:eq(reads["../other.lua"], nil, "invalid paths are rejected before mod:read")
local escapedTail, escapedTailCode = loader:load("src/..")
T:eq(escapedTail, nil, "a trailing parent segment has no export")
T:eq(escapedTailCode, "invalid_module_path",
  "a trailing parent segment cannot escape the mod")

local first, code, message = loader:load("good.lua")
T:eq(first and first.value, 42, "a sibling module returns its export")
T:eq(code, nil, "successful load has no error code")
T:eq(message, nil, "successful load has no error message")

local second = loader:load("good.lua")
T:check(second == first, "successful exports are cached by identity")
T:eq(reads["good.lua"], 1, "cached modules are read only once")

local missing, missingCode, missingMessage = loader:load("missing.lua")
T:eq(missing, nil, "missing module has no export")
T:eq(missingCode, "module_missing", "missing module has a stable code")
T:check(type(missingMessage) == "string" and missingMessage:find("missing.lua", 1, true),
  "missing module message names the requested path")

local invalid, invalidCode = loader:load("bad-syntax.lua")
T:eq(invalid, nil, "invalid module has no export")
T:eq(invalidCode, "module_compile_failed", "syntax failure has a stable code")

local thrown, thrownCode, thrownMessage = loader:load("throws.lua")
T:eq(thrown, nil, "throwing module has no export")
T:eq(thrownCode, "module_init_failed", "initialization failure has a stable code")
T:check(type(thrownMessage) == "string" and thrownMessage:find("boom", 1, true),
  "initialization message retains the cause")

T:finish()
