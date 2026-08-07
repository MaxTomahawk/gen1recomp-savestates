local Test = dofile("tests/testlib.lua")
local T = Test.new("snapshot")
local DataOnly = dofile("src/util/DataOnly.lua")
local Snapshot = dofile("src/state/Snapshot.lua")(DataOnly)
local Validator = dofile("src/state/SnapshotValidator.lua")(DataOnly)

local function checkpoint()
  return {
    format = 1,
    kind = "overworld",
    identity = {
      engineVersion = "0.9.0-dev",
      gameVersion = "red",
      playthroughId = "play-a",
    },
    save = { version = "red", money = 3000, flags = { GOT_STARTER = true } },
    runtime = { overworld = {
      map = "PALLET_TOWN", x = 5, y = 6, facing = "down", surfing = false,
    } },
  }
end

local function newSnapshot(overrides)
  local args = {
    id = "q00000001",
    modVersion = "0.1.0",
    modApi = 2,
    stateClass = "quick",
    trigger = "manual",
    createdAt = 100,
    locationId = "PALLET_TOWN",
    locationName = "PALLET TOWN",
    checkpoint = checkpoint(),
  }
  for key, value in pairs(overrides or {}) do args[key] = value end
  return Snapshot.new(args)
end

local context = {
  engineVersion = "0.9.0-dev",
  gameVersion = "red",
  playthroughId = "play-a",
  supportedKinds = { overworld = true },
}

local state, code, message = newSnapshot()
T:check(state ~= nil, "a complete quick state is constructed: " .. tostring(code or message))
T:eq(state.format, 1, "snapshot format is explicit")
T:eq(state.identity.modId, "savestates", "snapshot owns a stable mod id")
T:eq(state.identity.engineVersion, "0.9.0-dev", "engine version comes from checkpoint identity")
T:eq(state.metadata.stateKind, "overworld", "runtime kind comes from the checkpoint")

local slotState = newSnapshot({
  id = "s03_00000001", stateClass = "slot", slot = 3, label = "BEFORE MISTY",
})
local validSlot, validSlotCode, validSlotMessage = Validator.validate(slotState, context)
T:check(validSlot ~= nil,
  "slot generation metadata validates: " .. tostring(validSlotCode or validSlotMessage))
T:eq(validSlot.metadata.slot, 3, "slot number survives construction and validation")

local validated, validCode, validMessage, warnings = Validator.validate(state, context)
T:check(validated ~= nil,
  "a complete matching state validates: " .. tostring(validCode or validMessage))
T:eq(#warnings, 0, "matching engine versions have no compatibility warning")
T:check(validated ~= state and validated.checkpoint ~= state.checkpoint,
  "validation returns detached data")
validated.checkpoint.save.money = 1
T:eq(state.checkpoint.save.money, 3000, "mutating validated data cannot mutate stored input")

local sourceCheckpoint = checkpoint()
local detached = Snapshot.new({
  id = "q00000002", modVersion = "0.1.0", modApi = 2,
  stateClass = "quick", trigger = "manual", createdAt = 101,
  checkpoint = sourceCheckpoint,
})
sourceCheckpoint.save.money = 9
T:eq(detached.checkpoint.save.money, 3000,
  "construction detaches the engine checkpoint from live caller data")

local warningContext = {
  engineVersion = "0.9.1-dev", gameVersion = "red",
  playthroughId = "play-a", supportedKinds = { overworld = true },
}
local warned, _, _, versionWarnings = Validator.validate(state, warningContext)
T:check(warned ~= nil, "an engine version mismatch is warning-grade")
T:eq(versionWarnings[1], "engine_version_mismatch",
  "engine mismatch has a stable warning code")

local cases = {
  { "root", nil, "corrupt_metadata" },
  { "future format", function(s) s.format = 2 return s end, "bad_format" },
  { "wrong mod", function(s) s.identity.modId = "other" return s end, "corrupt_identity" },
  { "wrong game", function(s) s.identity.gameVersion = "blue" return s end, "wrong_game" },
  { "wrong playthrough", function(s) s.identity.playthroughId = "play-b" return s end,
    "wrong_playthrough" },
  { "missing checkpoint", function(s) s.checkpoint = nil return s end, "missing_checkpoint" },
  { "unsupported kind", function(s)
      s.metadata.stateKind, s.checkpoint.kind = "battle", "battle" return s
    end, "unsupported_runtime_kind" },
  { "corrupt metadata", function(s) s.metadata.createdAt = -1 return s end,
    "corrupt_metadata" },
  { "slot without number", function(s)
      s.metadata.stateClass, s.metadata.id = "slot", "s01_00000001" return s
    end, "corrupt_metadata" },
  { "non-slot with number", function(s) s.metadata.slot = 1 return s end,
    "corrupt_metadata" },
  { "kind disagreement", function(s) s.metadata.stateKind = "battle" return s end,
    "corrupt_metadata" },
  { "checkpoint game disagreement", function(s)
      s.checkpoint.identity.gameVersion = "blue" return s
    end, "corrupt_identity" },
}

for _, row in ipairs(cases) do
  local candidate = row[2] and row[2](newSnapshot()) or row[2]
  local result, errCode = Validator.validate(candidate, context)
  T:eq(result, nil, row[1] .. " is rejected")
  T:eq(errCode, row[3], row[1] .. " has the expected error code")
end

local invalidValues = {
  { name = "function", value = function() end },
  { name = "userdata", value = io.stdout },
  { name = "NaN", value = 0 / 0 },
  { name = "positive infinity", value = math.huge },
}
for _, row in ipairs(invalidValues) do
  local candidate = newSnapshot()
  candidate.checkpoint.save.bad = row.value
  local result, errCode = Validator.validate(candidate, context)
  T:eq(result, nil, row.name .. " is rejected")
  T:eq(errCode, "not_data_only", row.name .. " is classified as non-data")
end

local cyclic = newSnapshot()
cyclic.checkpoint.save.loop = cyclic.checkpoint.save
local cycleResult, cycleCode = Validator.validate(cyclic, context)
T:eq(cycleResult, nil, "cycles are rejected")
T:eq(cycleCode, "not_data_only", "cycles have the data-only error")

local metatabled = newSnapshot()
setmetatable(metatabled.checkpoint.save.flags, { __index = function() return true end })
local metaResult, metaCode = Validator.validate(metatabled, context)
T:eq(metaResult, nil, "behavioral metatables are rejected")
T:eq(metaCode, "not_data_only", "metatables have the data-only error")

T:finish()
