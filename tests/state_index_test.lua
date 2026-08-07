local Test = dofile("tests/testlib.lua")
local T = Test.new("state index")
local DataOnly = dofile("src/util/DataOnly.lua")
local StateIndex = dofile("src/state/StateIndex.lua")(DataOnly)
local Retention = dofile("src/state/Retention.lua")

local function metadata(id, class, createdAt, label)
  return {
    id = id,
    stateClass = class,
    createdAt = createdAt,
    stateKind = "overworld",
    trigger = class == "auto" and "location_enter" or "manual",
    locationId = "PALLET_TOWN",
    locationName = label or "PALLET TOWN",
  }
end

local index, code, message = StateIndex.new()
T:check(index ~= nil, "an empty format-1 index constructs: " .. tostring(code or message))

local quickIds = {}
for n = 1, 6 do
  local id = index:allocate("quick")
  quickIds[n] = id
  T:check(index:add("quick", metadata(id, "quick", n)), "quick state adds")
end
T:eq(quickIds[1], "q00000001", "quick ids are deterministic")
T:eq(quickIds[6], "q00000006", "quick ids advance monotonically")
local quick = index:list("quick")
T:eq(#quick, 6, "six quick states are listed")
T:eq(quick[1].id, quickIds[6], "quick list is newest first")
T:eq(quick[6].id, quickIds[1], "oldest quick is last")

local quickRemovals = Retention.selectRemovals(quick, 5)
T:eq(#quickRemovals, 1, "six quick states with max five removes one")
T:eq(quickRemovals[1], quickIds[1], "retention selects the oldest quick")
index:remove(quickRemovals[1])
T:eq(#index:list("quick"), 5, "removing retention selection leaves five quick states")

local autoIds = {}
for n = 1, 21 do
  local id = index:allocate("auto")
  autoIds[n] = id
  T:check(index:add("auto", metadata(id, "auto", 100 + n)), "auto state adds")
end
local auto = index:list("auto")
T:eq(#auto, 21, "twenty-one auto states are listed")
T:eq(auto[1].id, autoIds[21], "auto list is newest first")
local autoRemovals = Retention.selectRemovals(auto, 20)
T:eq(#autoRemovals, 1, "twenty-one autos with max twenty removes one")
T:eq(autoRemovals[1], autoIds[1], "retention selects the oldest auto")

local duplicateId = autoIds[21]
local replacement = metadata(duplicateId, "auto", 999, "UPDATED")
T:check(index:add("auto", replacement), "adding an existing id replaces metadata")
auto = index:list("auto")
T:eq(#auto, 21, "duplicate replacement does not grow history")
T:eq(auto[1].createdAt, 999, "replacement becomes the newest metadata")
T:eq(auto[1].locationName, "UPDATED", "replacement content is visible")

for slot = 1, 10 do
  local saved, slotCode = index:setSlot(slot,
    metadata(("slot%02d"):format(slot), "slot", 200 + slot))
  T:eq(saved, true, "permanent slot " .. slot .. " saves")
  T:eq(slotCode, nil, "valid slot has no error")
end
T:eq(index:slot(1).id, "slot01", "slot one has a fixed id")
T:eq(index:slot(10).id, "slot10", "slot ten has a fixed id")
local invalidSlot, invalidSlotCode = index:setSlot(11, metadata("slot11", "slot", 1))
T:eq(invalidSlot, nil, "slot eleven is refused")
T:eq(invalidSlotCode, "invalid_slot", "out-of-range slot has a stable code")
T:eq(#index:list("quick"), 5, "slot writes do not affect rolling quick history")
T:eq(#index:list("auto"), 21, "slot writes do not affect rolling auto history")

T:check(index:setSlot(3, nil), "clearing a slot succeeds")
T:eq(index:slot(3), nil, "cleared slot is empty")
T:eq(index:get("slot03"), nil, "clearing a slot removes its metadata")

T:check(index:setRecovery(metadata("recovery", "recovery", 500)),
  "recovery metadata saves")
T:eq(index:recovery().id, "recovery", "recovery has a fixed identity")
T:eq(#index:list("quick"), 5, "recovery stays outside quick history")
T:eq(#index:list("auto"), 21, "recovery stays outside auto history")

local record = index:record()
record.records[quickIds[6]].locationName = "MUTATED"
record.quick[1] = "other"
T:eq(index:get(quickIds[6]).locationName, "PALLET TOWN",
  "record output cannot mutate live metadata")
T:eq(index:list("quick")[1].id, quickIds[6], "record output cannot mutate live order")

local restored, restoredCode = StateIndex.new(index:record())
T:check(restored ~= nil, "a persisted index record reloads: " .. tostring(restoredCode))
T:eq(restored:list("quick")[1].id, quickIds[6], "reloaded index preserves ordering")
T:eq(restored:slot(1).id, "slot01", "reloaded index preserves permanent slots")
T:eq(restored:recovery().id, "recovery", "reloaded index preserves recovery")

local malformedCases = {
  { format = 2, sequence = 0, records = {}, quick = {}, auto = {}, slots = {} },
  { format = 1, sequence = 0, records = {}, quick = { "missing" }, auto = {}, slots = {} },
  { format = 1, sequence = 0,
    records = { q1 = metadata("q1", "quick", 1) },
    quick = { "q1", "q1" }, auto = {}, slots = {} },
}
for n, malformed in ipairs(malformedCases) do
  local bad, badCode = StateIndex.new(malformed)
  T:eq(bad, nil, "malformed index " .. n .. " is rejected")
  T:eq(badCode, "bad_index", "malformed index has a stable code")
end

local protected = {
  metadata("q2", "quick", 2),
  metadata("slot01", "slot", 1),
  metadata("q1", "quick", 1),
  metadata("recovery", "recovery", 0),
}
local protectedRemovals = Retention.selectRemovals(protected, 1)
T:eq(#protectedRemovals, 1, "retention counts only rolling entries")
T:eq(protectedRemovals[1], "q1", "slots and recovery are never retention targets")

T:finish()
