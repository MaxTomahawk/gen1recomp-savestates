local Test = {}
Test.__index = Test

function Test.new(name)
  return setmetatable({ name = name, checks = 0, failures = {} }, Test)
end

function Test:check(value, message)
  self.checks = self.checks + 1
  if value then return end
  self.failures[#self.failures + 1] = message or "check failed"
end

function Test:eq(actual, expected, message)
  self:check(actual == expected, (message or "values differ")
    .. (" (got %s, want %s)"):format(tostring(actual), tostring(expected)))
end

function Test:finish()
  if #self.failures > 0 then
    for _, failure in ipairs(self.failures) do
      io.stderr:write("FAIL ", failure, "\n")
    end
    error(("%s: %d/%d checks failed"):format(
      self.name, #self.failures, self.checks), 0)
  end
  print(("%s: %d/%d checks passed"):format(self.name, self.checks, self.checks))
end

return Test
