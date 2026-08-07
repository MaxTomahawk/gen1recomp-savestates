local Test = dofile("tests/testlib.lua")
local T = Test.new("migrations")
local DataOnly = dofile("src/util/DataOnly.lua")
local StateMigrations = dofile("src/state/StateMigrations.lua")(DataOnly)

local current = StateMigrations.new(1)
local now = { format = 1, metadata = { id = "q1" } }
local unchanged, code, message = current:run(now)
T:check(unchanged ~= nil, "current format passes: " .. tostring(code or message))
T:check(unchanged ~= now and unchanged.metadata ~= now.metadata,
  "current format still returns detached data")

local registry = StateMigrations.new(1)
local added, addCode = registry:add(0, function(snapshot)
  snapshot.format = 1
  snapshot.metadata.migrated = true
  return snapshot
end)
T:eq(added, true, "a forward migration registers")
T:eq(addCode, nil, "successful registration has no error")

local old = { format = 0, metadata = { id = "q1" } }
local migrated, migrateCode, migrateMessage = registry:run(old)
T:check(migrated ~= nil,
  "format zero migrates to one: " .. tostring(migrateCode or migrateMessage))
T:eq(migrated.format, 1, "migration advances the format")
T:eq(migrated.metadata.migrated, true, "migration applies its data change")
T:eq(old.format, 0, "migration does not mutate stored input format")
T:eq(old.metadata.migrated, nil, "migration does not mutate stored input data")

local duplicate, duplicateCode = registry:add(0, function() end)
T:eq(duplicate, nil, "duplicate migration is refused")
T:eq(duplicateCode, "duplicate_migration", "duplicate has a stable code")

local invalid, invalidCode = registry:add(1, function() end)
T:eq(invalid, nil, "a step at the current format is refused")
T:eq(invalidCode, "invalid_migration", "invalid step has a stable code")

local missing, missingCode = StateMigrations.new(1):run(old)
T:eq(missing, nil, "missing migration cannot guess an upgrade")
T:eq(missingCode, "missing_migration", "missing step has a stable code")

local future, futureCode = registry:run({ format = 2 })
T:eq(future, nil, "future state format is rejected")
T:eq(futureCode, "unsupported_format", "future format has a stable code")

local throwing = StateMigrations.new(1)
throwing:add(0, function() error("migration boom") end)
local thrown, thrownCode, thrownMessage = throwing:run(old)
T:eq(thrown, nil, "throwing migration has no output")
T:eq(thrownCode, "migration_failed", "throwing step has a stable code")
T:check(type(thrownMessage) == "string" and thrownMessage:find("migration boom", 1, true),
  "throwing step retains its cause")

local stalled = StateMigrations.new(1)
stalled:add(0, function(snapshot) return snapshot end)
local stalledResult, stalledCode = stalled:run(old)
T:eq(stalledResult, nil, "a migration that does not advance is rejected")
T:eq(stalledCode, "migration_failed", "stalled step has a stable code")

T:finish()
