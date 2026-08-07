local Test = dofile("tests/testlib.lua")
local T = Test.new("state store")
local DataOnly = dofile("src/util/DataOnly.lua")
local Snapshot = dofile("src/state/Snapshot.lua")(DataOnly)
local Validator = dofile("src/state/SnapshotValidator.lua")(DataOnly)
local StateMigrations = dofile("src/state/StateMigrations.lua")(DataOnly)
local StateIndex = dofile("src/state/StateIndex.lua")(DataOnly)
local StateStore = dofile("src/state/StateStore.lua")({
  DataOnly = DataOnly,
  StateIndex = StateIndex,
})

local function fakeStorage()
  local storage = {
    values = {}, calls = {}, failWrite = {}, failDelete = {}, corruptKeys = {},
  }
  function storage:context()
    return { gameVersion = "red", playthroughId = "play-a" }
  end
  function storage:write(_, key, value)
    self.calls[#self.calls + 1] = "write:" .. key
    if self.failWrite[key] then return false, "write_failed", "injected write failure" end
    local detached, code, message = DataOnly.copy(value)
    if not detached then return false, code, message end
    self.values[key] = detached
    return true
  end
  function storage:read(_, key)
    self.calls[#self.calls + 1] = "read:" .. key
    if self.corruptKeys[key] then return self.corruptKeys[key] end
    local value = self.values[key]
    if value == nil then return nil, "not_found", "missing" end
    return DataOnly.copy(value)
  end
  function storage:list(_, prefix)
    self.calls[#self.calls + 1] = "list:" .. (prefix or "")
    local out = {}
    for key in pairs(self.values) do
      if prefix == nil or prefix == "" or key == prefix
          or key:sub(1, #prefix + 1) == prefix .. "/" then
        out[#out + 1] = key
      end
    end
    for key in pairs(self.corruptKeys) do
      if prefix == nil or prefix == "" or key == prefix
          or key:sub(1, #prefix + 1) == prefix .. "/" then
        out[#out + 1] = key
      end
    end
    table.sort(out)
    return out
  end
  function storage:delete(_, key)
    self.calls[#self.calls + 1] = "delete:" .. key
    if self.failDelete[key] then return false, "write_failed", "injected delete failure" end
    if self.values[key] == nil and self.corruptKeys[key] == nil then
      return false, "not_found", "missing"
    end
    self.values[key], self.corruptKeys[key] = nil, nil
    return true
  end
  return storage
end

local function checkpoint()
  return {
    format = 1, kind = "overworld",
    identity = {
      engineVersion = "0.9.0-dev", gameVersion = "red", playthroughId = "play-a",
    },
    save = { version = "red", money = 3000 },
    runtime = { overworld = {
      map = "PALLET_TOWN", x = 5, y = 6, facing = "down", surfing = false,
    } },
  }
end

local function snapshot(id, class, createdAt, slot)
  return Snapshot.new({
    id = id, modVersion = "0.1.0", modApi = 2,
    stateClass = class, trigger = class == "auto" and "location_enter" or "manual",
    createdAt = createdAt, locationId = "PALLET_TOWN", locationName = "PALLET TOWN",
    slot = slot,
    checkpoint = checkpoint(),
  })
end

local migrations = StateMigrations.new(1)
local storage = fakeStorage()
local game = {}
local store = StateStore.new({
  storage = storage,
  game = game,
  validator = Validator,
  migrations = migrations,
  supportedKinds = { overworld = true },
})

local index, indexCode, indexMessage = store:loadIndex()
T:check(index ~= nil, "missing index initializes empty: " .. tostring(indexCode or indexMessage))
T:eq(#index:list("quick"), 0, "new index has no quick states")

local q1 = snapshot("q00000001", "quick", 1)
local wrote, writeCode, writeMessage = store:writeSnapshot(q1)
T:check(wrote == true, "valid payload writes: " .. tostring(writeCode or writeMessage))
T:check(index:add("quick", q1.metadata), "q1 metadata enters working index")
T:check(store:publish(index), "index publishes after payload")
T:eq(storage.calls[#storage.calls - 1], "write:states/q00000001",
  "payload is written before index publication")
T:eq(storage.calls[#storage.calls], "write:index", "index publication is the second write")

local reloaded = store:loadIndex()
T:eq(reloaded:list("quick")[1].id, "q00000001", "published index reloads")
local read, readCode, readMessage, warnings = store:readSnapshot("q00000001")
T:check(read ~= nil, "published payload reads: " .. tostring(readCode or readMessage))
T:eq(read.metadata.id, "q00000001", "read returns the selected payload")
T:eq(#warnings, 0, "matching read has no compatibility warning")

local q2 = snapshot("q00000002", "quick", 2)
T:check(store:writeSnapshot(q2), "q2 payload stages successfully")
T:check(index:add("quick", q2.metadata), "q2 enters working index")
storage.failWrite.index = true
local published, publishCode = store:publish(index)
storage.failWrite.index = nil
T:eq(published, nil, "failed index publication is reported")
T:eq(publishCode, "write_failed", "failed publication preserves storage error")
local stillPublished = store:loadIndex()
T:eq(#stillPublished:list("quick"), 1, "failed publication leaves old index valid")
T:eq(stillPublished:list("quick")[1].id, "q00000001", "old index still names q1")
local orphans = store:scanOrphans()
T:eq(#orphans, 1, "failed publication leaves one discoverable orphan")
T:eq(orphans[1], "q00000002", "the unreferenced q2 payload is the orphan")

storage.calls = {}
local updated, deleteCode, deleteMessage = store:delete(stillPublished, "q00000001")
T:check(updated ~= nil, "published q1 deletes: " .. tostring(deleteCode or deleteMessage))
T:eq(storage.calls[1], "write:index", "delete unpublishes metadata first")
T:eq(storage.calls[2], "delete:states/q00000001", "payload cleanup follows unpublish")
T:eq(#updated:list("quick"), 0, "returned index reflects deletion")

local missing, missingCode = store:readSnapshot("q00000001")
T:eq(missing, nil, "missing payload is unavailable")
T:eq(missingCode, "payload_missing", "missing payload has a store-level code")

local bad = snapshot("q00000003", "quick", 3)
bad.metadata.createdAt = -1
storage.values["states/q00000003"] = bad
local corrupt, corruptCode = store:readSnapshot("q00000003")
T:eq(corrupt, nil, "corrupt payload is unavailable")
T:eq(corruptCode, "corrupt_metadata", "corrupt payload retains validator code")
T:check(storage.values["states/q00000003"] ~= nil,
  "corrupt payload is retained for diagnosis/recovery")

local recovery = snapshot("recovery", "recovery", 4)
T:check(store:saveRecovery(recovery), "recovery payload writes independently")
local recovered = store:loadRecovery()
T:eq(recovered.metadata.id, "recovery", "recovery payload roundtrips")
T:eq(#store:loadIndex():list("quick"), 0, "recovery does not enter rolling index")

local replacementRecovery = snapshot("recovery", "recovery", 6)
replacementRecovery.checkpoint.save.money = 123
storage.failWrite.recovery = true
local recoveryWrite, recoveryWriteCode = store:saveRecovery(replacementRecovery)
storage.failWrite.recovery = nil
T:eq(recoveryWrite, nil, "failed recovery replacement is reported")
T:eq(recoveryWriteCode, "write_failed", "recovery replacement retains storage error")
T:eq(store:loadRecovery().checkpoint.save.money, 3000,
  "failed recovery replacement leaves prior recovery readable")

local wrongProfile, wrongProfileCode = store:readSnapshot(
  "q00000002", { playthroughId = "play-b" })
T:eq(wrongProfile, nil, "another playthrough cannot read a payload")
T:eq(wrongProfileCode, "wrong_playthrough", "profile mismatch retains validator code")

local q5 = snapshot("q00000005", "quick", 7)
local cleanupIndex = store:loadIndex()
T:check(store:writeSnapshot(q5), "cleanup-failure fixture payload writes")
T:check(cleanupIndex:add("quick", q5.metadata), "cleanup-failure metadata adds")
T:check(store:publish(cleanupIndex), "cleanup-failure index publishes")
storage.failDelete["states/q00000005"] = true
local logicallyDeleted, cleanupCode = store:delete(cleanupIndex, "q00000005")
storage.failDelete["states/q00000005"] = nil
T:check(logicallyDeleted ~= nil, "failed cleanup still returns published updated index")
T:eq(cleanupCode, "orphaned_payload", "failed cleanup is an explicit recoverable warning")
T:eq(#store:loadIndex():list("quick"), 0, "failed payload cleanup stays unpublished")
local cleanupOrphans = store:scanOrphans()
local foundCleanupOrphan = false
for _, id in ipairs(cleanupOrphans) do
  if id == "q00000005" then foundCleanupOrphan = true end
end
T:check(foundCleanupOrphan, "failed payload cleanup remains discoverable as an orphan")

local migratingRegistry = StateMigrations.new(1)
migratingRegistry:add(0, function(value)
  value.format = 1
  return value
end)
local migratingStore = StateStore.new({
  storage = storage, game = game, validator = Validator,
  migrations = migratingRegistry, supportedKinds = { overworld = true },
})
local legacy = snapshot("q00000004", "quick", 5)
legacy.format = 0
storage.values["states/q00000004"] = legacy
local migrated = migratingStore:readSnapshot("q00000004")
T:eq(migrated.format, 1, "stored older format runs explicit migration before validation")
T:eq(storage.values["states/q00000004"].format, 0,
  "read migration does not rewrite stored input implicitly")

local rollingStorage = fakeStorage()
local rollingStore = StateStore.new({
  storage = rollingStorage, game = game, validator = Validator,
  migrations = migrations, supportedKinds = { overworld = true },
})
local rollingIndex = rollingStore:loadIndex()
local rollingQ1 = snapshot("q00000001", "quick", 10)
T:check(rollingStore:writeSnapshot(rollingQ1), "rolling fixture payload writes")
T:check(rollingIndex:add("quick", rollingQ1.metadata), "rolling fixture metadata adds")
T:check(rollingStore:publish(rollingIndex), "rolling fixture index publishes")

local rollingQ2 = snapshot("q00000002", "quick", 11)
local nextRolling = rollingStore:loadIndex()
T:check(nextRolling:add("quick", rollingQ2.metadata), "new rolling metadata adds")
T:check(nextRolling:remove("q00000001"), "trimmed rolling metadata is removed")
rollingStorage.calls = {}
local committed, commitCode, commitMessage = rollingStore:commitRolling(
  nextRolling, rollingQ2, { "q00000001" })
T:check(committed == true,
  "rolling transaction commits: " .. tostring(commitCode or commitMessage))
T:eq(rollingStorage.calls[1], "write:states/q00000002",
  "rolling transaction stages new payload first")
T:eq(rollingStorage.calls[2], "write:index",
  "rolling transaction publishes final index second")
T:eq(rollingStorage.calls[3], "delete:states/q00000001",
  "rolling transaction cleans trimmed payload after publication")
T:eq(rollingStore:loadIndex():list("quick")[1].id, "q00000002",
  "rolling transaction publishes the new newest state")
T:eq(rollingStorage.values["states/q00000001"], nil,
  "successful rolling transaction removes trimmed payload")

local rollingQ3 = snapshot("q00000003", "quick", 12)
local failedRolling = rollingStore:loadIndex()
T:check(failedRolling:add("quick", rollingQ3.metadata), "failed-publication metadata adds")
T:check(failedRolling:remove("q00000002"), "failed-publication trim prepares")
rollingStorage.failWrite.index = true
local failedCommit, failedCommitCode = rollingStore:commitRolling(
  failedRolling, rollingQ3, { "q00000002" })
rollingStorage.failWrite.index = nil
T:eq(failedCommit, nil, "failed rolling publication is reported")
T:eq(failedCommitCode, "write_failed", "failed rolling publication preserves error")
T:eq(rollingStore:loadIndex():list("quick")[1].id, "q00000002",
  "failed rolling publication leaves old index authoritative")
T:check(rollingStorage.values["states/q00000002"] ~= nil,
  "failed rolling publication leaves old payload intact")
T:check(rollingStorage.values["states/q00000003"] ~= nil,
  "failed rolling publication leaves staged payload discoverable as orphan")

local rollingQ4 = snapshot("q00000004", "quick", 13)
local cleanupRolling = rollingStore:loadIndex()
T:check(cleanupRolling:add("quick", rollingQ4.metadata), "cleanup-warning metadata adds")
T:check(cleanupRolling:remove("q00000002"), "cleanup-warning trim prepares")
rollingStorage.failDelete["states/q00000002"] = true
local cleanupCommitted, cleanupCommitCode = rollingStore:commitRolling(
  cleanupRolling, rollingQ4, { "q00000002" })
rollingStorage.failDelete["states/q00000002"] = nil
T:check(cleanupCommitted == true, "cleanup failure does not undo published history")
T:eq(cleanupCommitCode, "orphaned_payload", "cleanup failure returns warning code")
T:eq(rollingStore:loadIndex():list("quick")[1].id, "q00000004",
  "cleanup failure keeps new index authoritative")
T:check(rollingStorage.values["states/q00000002"] ~= nil,
  "cleanup failure leaves old payload as recoverable orphan")

local inconsistentIndex = rollingStore:loadIndex()
local inconsistent = snapshot("q00000005", "quick", 14)
local wrongMetadata = DataOnly.copy(inconsistent.metadata)
wrongMetadata.createdAt = 99
T:check(inconsistentIndex:add("quick", wrongMetadata), "inconsistent fixture metadata adds")
local rejectedCommit, rejectedCommitCode = rollingStore:commitRolling(
  inconsistentIndex, inconsistent, {})
T:eq(rejectedCommit, nil, "index/payload metadata disagreement is rejected")
T:eq(rejectedCommitCode, "bad_metadata", "metadata disagreement has stable code")
T:eq(rollingStorage.values["states/q00000005"], nil,
  "rejected rolling transaction writes no payload")

local slotStorage = fakeStorage()
local slotStore = StateStore.new({
  storage = slotStorage, game = game, validator = Validator,
  migrations = migrations, supportedKinds = { overworld = true },
})
local slotIndex = slotStore:loadIndex()
local slotId1 = slotIndex:allocate("slot", 1)
local slotOne = snapshot(slotId1, "slot", 20, 1)
T:check(slotIndex:setSlot(1, slotOne.metadata), "first slot generation prepares")
T:check(slotStore:commitSlot(slotIndex, slotOne, {}), "first slot generation commits")
T:eq(slotStore:loadIndex():slot(1).id, slotId1, "slot index points at first generation")

local failedSlotIndex = slotStore:loadIndex()
local slotId2 = failedSlotIndex:allocate("slot", 1)
local slotTwo = snapshot(slotId2, "slot", 21, 1)
slotTwo.checkpoint.save.money = 4000
T:check(failedSlotIndex:setSlot(1, slotTwo.metadata), "slot overwrite prepares")
slotStorage.failWrite.index = true
local failedSlot, failedSlotCode = slotStore:commitSlot(
  failedSlotIndex, slotTwo, { slotId1 })
slotStorage.failWrite.index = nil
T:eq(failedSlot, nil, "failed slot publication is reported")
T:eq(failedSlotCode, "write_failed", "failed slot publication preserves error")
T:eq(slotStore:loadIndex():slot(1).id, slotId1,
  "failed slot publication leaves previous generation indexed")
T:eq(slotStore:readSnapshot(slotId1).checkpoint.save.money, 3000,
  "failed slot publication leaves previous generation loadable")
T:check(slotStorage.values["states/" .. slotId2] ~= nil,
  "failed slot publication leaves new generation as orphan")

local successfulSlotIndex = slotStore:loadIndex()
local slotId3 = successfulSlotIndex:allocate("slot", 1)
local slotThree = snapshot(slotId3, "slot", 22, 1)
slotThree.checkpoint.save.money = 5000
T:check(successfulSlotIndex:setSlot(1, slotThree.metadata),
  "successful slot overwrite prepares")
slotStorage.calls = {}
local committedSlot, committedSlotCode, committedSlotMessage = slotStore:commitSlot(
  successfulSlotIndex, slotThree, { slotId1 })
T:check(committedSlot == true,
  "slot overwrite commits: " .. tostring(committedSlotCode or committedSlotMessage))
T:eq(slotStorage.calls[1], "write:states/" .. slotId3,
  "slot overwrite stages unique generation first")
T:eq(slotStorage.calls[2], "write:index", "slot overwrite publishes index second")
T:eq(slotStorage.calls[3], "delete:states/" .. slotId1,
  "slot overwrite deletes old generation last")
T:eq(slotStore:loadIndex():slot(1).id, slotId3,
  "successful slot overwrite points at new generation")
T:eq(slotStorage.values["states/" .. slotId1], nil,
  "successful slot overwrite removes old generation")

local wrongSlotCommit, wrongSlotCommitCode = slotStore:commitSlot(
  successfulSlotIndex, rollingQ4, {})
T:eq(wrongSlotCommit, nil, "rolling snapshot cannot use slot transaction")
T:eq(wrongSlotCommitCode, "invalid_class", "wrong slot transaction class is explicit")

storage.corruptKeys.index = { format = 99 }
storage.values.index = nil
local badIndex, badIndexCode = store:loadIndex()
T:eq(badIndex, nil, "present corrupt index is not mistaken for first run")
T:eq(badIndexCode, "bad_index", "corrupt index has a stable code")

T:finish()
