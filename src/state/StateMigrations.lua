return function(DataOnly)
  local StateMigrations = {}
  StateMigrations.__index = StateMigrations

  function StateMigrations.new(currentFormat)
    assert(type(currentFormat) == "number" and currentFormat >= 1
      and currentFormat % 1 == 0, "current format must be a positive integer")
    return setmetatable({ currentFormat = currentFormat, steps = {} }, StateMigrations)
  end

  function StateMigrations:add(fromFormat, fn)
    if type(fromFormat) ~= "number" or fromFormat < 0 or fromFormat % 1 ~= 0
        or fromFormat >= self.currentFormat or type(fn) ~= "function" then
      return nil, "invalid_migration", "Migration must be a forward function below current format."
    end
    if self.steps[fromFormat] then
      return nil, "duplicate_migration", "A migration already exists for this format."
    end
    self.steps[fromFormat] = fn
    return true
  end

  function StateMigrations:run(snapshot)
    local copy, dataCode, dataMessage = DataOnly.copy(snapshot)
    if not copy then return nil, dataCode, dataMessage end
    local format = copy.format
    if type(format) ~= "number" or format < 0 or format % 1 ~= 0 then
      return nil, "unsupported_format", "Snapshot format is missing or invalid."
    end
    if format > self.currentFormat then
      return nil, "unsupported_format", "Snapshot was written by a newer format."
    end

    while format < self.currentFormat do
      local step = self.steps[format]
      if not step then
        return nil, "missing_migration",
          ("No migration exists from snapshot format %d."):format(format)
      end
      local ok, result = pcall(step, copy)
      if not ok then
        return nil, "migration_failed",
          ("Snapshot migration from format %d failed: %s"):format(format, tostring(result))
      end
      if type(result) ~= "table" or result.format ~= format + 1 then
        return nil, "migration_failed",
          ("Snapshot migration from format %d did not advance exactly one format.")
            :format(format)
      end
      copy, dataCode, dataMessage = DataOnly.copy(result)
      if not copy then
        return nil, "migration_failed",
          "Snapshot migration produced non-data output: " .. tostring(dataMessage or dataCode)
      end
      format = copy.format
    end
    return copy
  end

  return StateMigrations
end
