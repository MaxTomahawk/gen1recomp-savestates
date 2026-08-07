local Test = dofile("tests/testlib.lua")
local T = Test.new("save state service")
local DataOnly = dofile("src/util/DataOnly.lua")
local Snapshot = dofile("src/state/Snapshot.lua")(DataOnly)
local Validator = dofile("src/state/SnapshotValidator.lua")(DataOnly)
local StateMigrations = dofile("src/state/StateMigrations.lua")(DataOnly)
local StateIndex = dofile("src/state/StateIndex.lua")(DataOnly)
local Retention = dofile("src/state/Retention.lua")
local Deduplicator = dofile("src/autosave/Deduplicator.lua")
local Canonical = dofile("src/util/Canonical.lua")(DataOnly)
local Fingerprint = dofile("src/util/Fingerprint.lua")(Canonical)
local StateStore = dofile("src/state/StateStore.lua")({
  DataOnly = DataOnly,
  StateIndex = StateIndex,
})

local function checkpoint(money, map)
  map = map or "PALLET_TOWN"
  return {
    format = 1,
    kind = "overworld",
    identity = {
      engineVersion = "0.9.0-dev",
      gameVersion = "red",
      playthroughId = "play-a",
    },
    save = {
      version = "red",
      meta = { playthroughId = "play-a" },
      player = { map = map, x = 5, y = 6, facing = "down", surfing = false },
      money = money,
    },
    runtime = { overworld = {
      map = map, x = 5, y = 6, facing = "down", surfing = false,
    } },
  }
end

local function environment(args)
  args = args or {}
  local events = {}
  local game = { current = checkpoint(args.money or 100) }
  local storage = {
    values = {}, failWrite = {}, failRead = {}, failDelete = {}, events = events,
  }
  function storage:context()
    return { gameVersion = "red", playthroughId = "play-a" }
  end
  function storage:write(_, key, value)
    events[#events + 1] = "write:" .. key
    if self.failWrite[key] then return nil, "write_failed", "injected write failure" end
    self.values[key] = assert(DataOnly.copy(value))
    return true
  end
  function storage:read(_, key)
    events[#events + 1] = "read:" .. key
    if self.failRead[key] then return nil, "read_failed", "injected read failure" end
    local value = self.values[key]
    if value == nil then return nil, "not_found", "missing" end
    return DataOnly.copy(value)
  end
  function storage:list(_, prefix)
    events[#events + 1] = "list:" .. (prefix or "")
    local keys = {}
    for key in pairs(self.values) do
      if not prefix or key == prefix or key:sub(1, #prefix + 1) == prefix .. "/" then
        keys[#keys + 1] = key
      end
    end
    table.sort(keys)
    return keys
  end
  function storage:delete(_, key)
    events[#events + 1] = "delete:" .. key
    if self.failDelete[key] then return nil, "write_failed", "injected delete failure" end
    if self.values[key] == nil then return nil, "not_found", "missing" end
    self.values[key] = nil
    return true
  end

  local checkpoints = {
    events = events,
    capability = { canCapture = true, canRestore = true, kind = "overworld" },
  }
  function checkpoints:inspect()
    events[#events + 1] = "inspect"
    return DataOnly.copy(self.capability)
  end
  function checkpoints:capture(targetGame)
    events[#events + 1] = "capture"
    if self.captureFailure then
      return nil, self.captureFailure, "injected capture failure"
    end
    return DataOnly.copy(targetGame.current)
  end
  function checkpoints:restore(targetGame, target)
    events[#events + 1] = "restore:" .. tostring(target.save.money)
    if self.restoreFailure then
      return false, self.restoreFailure, "injected restore failure"
    end
    targetGame.current = assert(DataOnly.copy(target))
    return true
  end

  local migrations = StateMigrations.new(1)
  local function storeFactory(targetGame)
    return StateStore.new({
      storage = storage,
      game = targetGame,
      validator = Validator,
      migrations = migrations,
      supportedKinds = { overworld = true },
    })
  end
  local notifications = {}
  local now = args.now or 1000
  local limit = args.limit or 5
  local autoLimit = args.autoLimit or 20
  local Service = dofile("src/service/SaveStateService.lua")({
    Snapshot = Snapshot,
    Retention = Retention,
    Fingerprint = Fingerprint,
    Deduplicator = Deduplicator,
  })
  local service = Service.new({
    checkpoints = checkpoints,
    storeFactory = storeFactory,
    clock = function() return now end,
    quickLimit = function() return limit end,
    autoLimit = function() return autoLimit end,
    modVersion = "0.1.0",
    modApi = 2,
    notify = function(kind, detail)
      notifications[#notifications + 1] = { kind = kind, detail = detail }
    end,
  })
  return {
    game = game,
    storage = storage,
    checkpoints = checkpoints,
    service = service,
    notifications = notifications,
    events = events,
    storeFactory = storeFactory,
    setNow = function(value) now = value end,
    setLimit = function(value) limit = value end,
    setAutoLimit = function(value) autoLimit = value end,
  }
end

local unsafe = environment()
unsafe.checkpoints.capability = {
  canCapture = false, canRestore = false, kind = "overworld",
  reason = "script_busy", message = "Wait for the active script to finish.",
}
local unsafeSave, unsafeCode = unsafe.service:quickSave(unsafe.game)
T:eq(unsafeSave, nil, "unsafe quicksave is rejected")
T:eq(unsafeCode, "script_busy", "unsafe quicksave preserves capability reason")
T:eq(unsafe.events[1], "inspect", "unsafe quicksave only inspects capability")
T:eq(#unsafe.events, 1, "unsafe quicksave does not capture or persist")
T:eq(unsafe.notifications[1].kind, "save_rejected", "unsafe save emits refusal notice")

local happy = environment({ money = 3000, now = 1234 })
local saved, saveCode, saveMessage = happy.service:quickSave(happy.game)
T:check(saved ~= nil, "quicksave succeeds: " .. tostring(saveCode or saveMessage))
T:eq(saved.metadata.id, "q00000001", "first quicksave receives monotonic id")
T:eq(saved.metadata.stateClass, "quick", "quicksave records its state class")
T:eq(saved.metadata.locationId, "PALLET_TOWN", "quicksave records public map id")
T:eq(saved.metadata.locationName, "PALLET TOWN", "fallback map label is readable")
T:eq(saved.metadata.createdAt, 1234, "quicksave uses injected wall clock")
T:check(type(saved.metadata.fingerprint) == "string"
  and #saved.metadata.fingerprint == 16, "quicksave records semantic fingerprint")
local happyIndex = happy.storeFactory(happy.game):loadIndex()
T:eq(happyIndex:list("quick")[1].id, "q00000001", "quicksave publishes history")
T:check(happy.storage.values["states/q00000001"] ~= nil,
  "quicksave payload persists independently")
T:eq(happy.notifications[1].kind, "quick_saved", "successful save emits notification")
T:eq(happy.notifications[1].detail.count, 1, "save notification reports history count")
local happySummary = happy.service:summary(happy.game)
T:eq(happySummary.quickCount, 1, "summary reports quick history count")
T:eq(happySummary.autoCount, 0, "summary reports empty auto history")
T:eq(happySummary.slotCount, 0, "summary reports no occupied slots")
T:eq(happySummary.slotCapacity, 10, "summary reports permanent slot capacity")
T:eq(happySummary.undoAvailable, false, "summary reports no recovery before a load")

happy.setLimit(2)
happy.setNow(1235)
happy.game.current = checkpoint(3100, "ROUTE_1")
T:check(happy.service:quickSave(happy.game) ~= nil, "second quicksave succeeds")
happy.setNow(1236)
happy.game.current = checkpoint(3200, "VIRIDIAN_CITY")
T:check(happy.service:quickSave(happy.game) ~= nil, "third quicksave succeeds")
happyIndex = happy.storeFactory(happy.game):loadIndex()
T:eq(#happyIndex:list("quick"), 2, "rolling quick history honors current limit")
T:eq(happyIndex:list("quick")[1].id, "q00000003", "rolling history stays newest-first")
T:eq(happyIndex:list("quick")[2].id, "q00000002", "second newest state is retained")
T:eq(happy.storage.values["states/q00000001"], nil, "oldest trimmed payload is removed")

local slots = environment({ money = 500 })
local emptySlots = slots.service:listSlots(slots.game)
T:eq(#emptySlots, 10, "slot listing always exposes ten permanent positions")
T:eq(emptySlots[1].occupied, false, "fresh permanent slot is empty")
local slotSaved, slotSaveCode, slotSaveMessage = slots.service:saveSlot(slots.game, 3)
T:check(slotSaved ~= nil,
  "saving an empty permanent slot succeeds: " .. tostring(slotSaveCode or slotSaveMessage))
T:eq(slotSaved.metadata.slot, 3, "slot snapshot records logical slot number")
T:eq(slotSaved.metadata.label, "SLOT 03", "slot receives conservative default label")
T:check(slotSaved.metadata.id:match("^s03_%d%d%d%d%d%d%d%d$") ~= nil,
  "slot payload uses a unique generation id")
local firstSlotId = slotSaved.metadata.id
local listedSlots = slots.service:listSlots(slots.game)
T:eq(listedSlots[3].occupied, true, "saved permanent slot is occupied")
T:eq(listedSlots[3].available, true, "saved permanent slot is loadable")
T:eq(listedSlots[3].metadata.label, "SLOT 03", "slot listing exposes saved label")

slots.game.current = checkpoint(600, "ROUTE_1")
slots.storage.failWrite.index = true
local failedOverwrite, failedOverwriteCode = slots.service:saveSlot(
  slots.game, 3, "BEFORE BROCK")
slots.storage.failWrite.index = nil
T:eq(failedOverwrite, nil, "failed slot index publication rejects overwrite")
T:eq(failedOverwriteCode, "write_failed", "failed slot overwrite preserves error")
local preservedSlot = slots.service:listSlots(slots.game)[3]
T:eq(preservedSlot.metadata.id, firstSlotId,
  "failed slot overwrite leaves previous generation indexed")
T:eq(slots.storeFactory(slots.game):readSnapshot(firstSlotId).checkpoint.save.money, 500,
  "failed slot overwrite leaves previous generation loadable")

local overwritten, overwriteCode, overwriteMessage = slots.service:saveSlot(
  slots.game, 3, "BEFORE BROCK")
T:check(overwritten ~= nil,
  "slot overwrite succeeds: " .. tostring(overwriteCode or overwriteMessage))
T:check(overwritten.metadata.id ~= firstSlotId,
  "successful slot overwrite publishes a new generation")
T:eq(overwritten.metadata.label, "BEFORE BROCK", "slot overwrite stores custom label")
T:eq(slots.storage.values["states/" .. firstSlotId], nil,
  "successful slot overwrite cleans previous generation")

local renamed, renameCode, renameMessage = slots.service:renameSlot(
  slots.game, 3, "ROUTE ONE")
T:check(renamed ~= nil, "slot rename succeeds: " .. tostring(renameCode or renameMessage))
T:eq(renamed.metadata.label, "ROUTE ONE", "slot rename changes metadata label")
T:eq(renamed.checkpoint.save.money, 600, "slot rename preserves checkpoint progress")
local renamedId = renamed.metadata.id
local badName, badNameCode = slots.service:renameSlot(slots.game, 3, "BAD/NAME")
T:eq(badName, nil, "unsupported slot label characters are rejected")
T:eq(badNameCode, "invalid_label", "bad slot label has stable code")

slots.game.current = checkpoint(700)
local loadedSlot, loadedSlotCode, loadedSlotMessage = slots.service:loadSlot(slots.game, 3)
T:check(loadedSlot ~= nil,
  "permanent slot loads: " .. tostring(loadedSlotCode or loadedSlotMessage))
T:eq(slots.game.current.save.money, 600, "permanent slot restores its checkpoint")

local pinnedSource = slots.service:quickSave(slots.game)
slots.game.current = checkpoint(800)
local pinned, pinCode, pinMessage = slots.service:pinToSlot(
  slots.game, pinnedSource.metadata.id, 4, "PINNED")
T:check(pinned ~= nil, "quick state pins to permanent slot: "
  .. tostring(pinCode or pinMessage))
T:eq(pinned.metadata.slot, 4, "pinned state targets selected slot")
T:eq(pinned.metadata.label, "PINNED", "pinned state stores selected label")
T:eq(pinned.checkpoint.save.money, 600, "pin copies source checkpoint, not live runtime")

local deletedSlot, deletedSlotCode, deletedSlotMessage = slots.service:deleteSlot(
  slots.game, 3)
T:check(deletedSlot == true,
  "slot deletion succeeds: " .. tostring(deletedSlotCode or deletedSlotMessage))
T:eq(slots.service:listSlots(slots.game)[3].occupied, false,
  "deleted permanent slot becomes empty")
T:eq(slots.storage.values["states/" .. renamedId], nil,
  "slot deletion removes selected generation payload")
local invalidSlotSave, invalidSlotSaveCode = slots.service:saveSlot(slots.game, 11)
T:eq(invalidSlotSave, nil, "slot eleven cannot be saved")
T:eq(invalidSlotSaveCode, "invalid_slot", "invalid slot save has stable code")

local captureFailure = environment()
captureFailure.checkpoints.captureFailure = "capture_failed"
local failedSave, failedSaveCode = captureFailure.service:quickSave(captureFailure.game)
T:eq(failedSave, nil, "capture failure aborts quicksave")
T:eq(failedSaveCode, "capture_failed", "capture failure preserves engine code")
T:eq(captureFailure.storage.values.index, nil, "capture failure publishes no index")
T:eq(captureFailure.notifications[1].kind, "save_failed", "capture failure is notified")

local autos = environment({ money = 100, now = 200, autoLimit = 2 })
local autoOne, autoOneCode, autoOneMessage = autos.service:autoSave(
  autos.game, "location_enter", { mapId = "PALLET_TOWN", contextKey = "PALLET_TOWN" })
T:check(autoOne ~= nil,
  "location autosave succeeds: " .. tostring(autoOneCode or autoOneMessage))
T:eq(autoOne.metadata.stateClass, "auto", "autosave records auto class")
T:eq(autoOne.metadata.trigger, "location_enter", "autosave records semantic trigger")
T:eq(autoOne.metadata.contextKey, "PALLET_TOWN", "autosave records cooldown context")
T:eq(autos.notifications[#autos.notifications].kind, "auto_saved",
  "autosave emits notification")

autos.setNow(202)
autos.game.current = checkpoint(101)
local cooled, cooledCode = autos.service:autoSave(
  autos.game, "location_enter", { mapId = "PALLET_TOWN", contextKey = "PALLET_TOWN" })
T:eq(cooled, false, "same autosave context inside cooldown is skipped")
T:eq(cooledCode, "deduplicated", "cooldown skip has stable non-error code")
T:eq(#autos.storeFactory(autos.game):loadIndex():list("auto"), 1,
  "cooldown skip does not grow history")

autos.setNow(206)
autos.game.current = checkpoint(100)
local replacedAuto = autos.service:autoSave(
  autos.game, "location_enter", { mapId = "PALLET_TOWN", contextKey = "PALLET_TOWN" })
T:check(replacedAuto ~= nil, "semantic duplicate after cooldown replaces")
T:check(replacedAuto.metadata.id ~= autoOne.metadata.id,
  "semantic replacement uses a new transactional generation")
local autoIndex = autos.storeFactory(autos.game):loadIndex()
T:eq(#autoIndex:list("auto"), 1, "semantic replacement does not grow history")
T:eq(autos.storage.values["states/" .. autoOne.metadata.id], nil,
  "semantic replacement cleans prior payload generation")

autos.setNow(207)
autos.game.current = checkpoint(102)
T:check(autos.service:autoSave(autos.game, "trainer_battle_start", {
  mapId = "PALLET_TOWN", contextKey = "TRAINER:1",
}), "different autosave trigger appends")
autos.setNow(213)
autos.game.current = checkpoint(103, "ROUTE_1")
T:check(autos.service:autoSave(autos.game, "location_enter", {
  mapId = "ROUTE_1", contextKey = "ROUTE_1",
}), "new location autosave appends")
autoIndex = autos.storeFactory(autos.game):loadIndex()
T:eq(#autoIndex:list("auto"), 2, "autosave retention honors configured limit")
T:eq(autoIndex:list("auto")[1].locationId, "ROUTE_1",
  "autosave history stays newest-first")

local staleAuto = environment({ money = 100, now = 300 })
local stale, staleCode = staleAuto.service:autoSave(staleAuto.game, "location_enter", {
  mapId = "ROUTE_1", contextKey = "ROUTE_1",
})
T:eq(stale, nil, "stale deferred location event does not save another map")
T:eq(staleCode, "stale_trigger", "stale location event has stable code")
T:eq(staleAuto.storage.values.index, nil, "stale location event publishes nothing")

local writeFailure = environment()
writeFailure.storage.failWrite["states/q00000001"] = true
local unwritten, unwrittenCode = writeFailure.service:quickSave(writeFailure.game)
T:eq(unwritten, nil, "payload write failure aborts quicksave")
T:eq(unwrittenCode, "write_failed", "payload write failure preserves storage code")
T:eq(writeFailure.storage.values.index, nil, "payload failure publishes no index")

local empty = environment()
local noQuick, noQuickCode = empty.service:quickLoad(empty.game)
T:eq(noQuick, nil, "quickload with empty history is rejected")
T:eq(noQuickCode, "no_quick_save", "empty history has product-level error code")
T:eq(empty.notifications[1].kind, "load_failed", "empty quickload is notified")

local load = environment({ money = 100 })
local target = load.service:quickSave(load.game)
load.game.current = checkpoint(999, "ROUTE_1")
load.events = load.events
for i = #load.events, 1, -1 do load.events[i] = nil end
local loaded, loadCode, loadMessage = load.service:quickLoad(load.game)
T:check(loaded ~= nil, "newest quickload succeeds: " .. tostring(loadCode or loadMessage))
T:eq(loaded.metadata.id, target.metadata.id, "quickload returns selected snapshot")
T:eq(load.game.current.save.money, 100, "quickload restores selected progress")
local recovery = load.storeFactory(load.game):loadRecovery()
T:eq(recovery.checkpoint.save.money, 999, "quickload durably captures pre-load recovery")
local recoveryWrite, restoreCall
for index, event in ipairs(load.events) do
  if event == "write:recovery" then recoveryWrite = index end
  if event == "restore:100" then restoreCall = index end
end
T:check(recoveryWrite and restoreCall and recoveryWrite < restoreCall,
  "recovery is persisted before runtime mutation")
T:eq(load.notifications[#load.notifications].kind, "state_loaded",
  "successful load emits notification")
T:eq(load.service:summary(load.game).undoAvailable, true,
  "summary exposes durable undo after successful load")

local skipCorrupt = environment({ money = 10 })
T:check(skipCorrupt.service:quickSave(skipCorrupt.game), "older valid quick fixture saves")
skipCorrupt.game.current = checkpoint(20)
T:check(skipCorrupt.service:quickSave(skipCorrupt.game), "new corrupt quick fixture saves")
skipCorrupt.storage.values["states/q00000002"].metadata.createdAt = -1
skipCorrupt.game.current = checkpoint(30)
local skipped, skippedCode, skippedMessage = skipCorrupt.service:quickLoad(skipCorrupt.game)
T:check(skipped ~= nil, "corrupt newest quick is skipped: "
  .. tostring(skippedCode or skippedMessage))
T:eq(skipped.metadata.id, "q00000001", "quickload selects newest valid older quick")
T:eq(skipCorrupt.game.current.save.money, 10, "older valid quick restores correctly")
local listed = skipCorrupt.service:listStates(skipCorrupt.game, "quick")
T:eq(#listed, 2, "state listing keeps corrupt entries visible")
T:eq(listed[1].metadata.id, "q00000002", "state listing stays newest-first")
T:eq(listed[1].available, false, "corrupt list entry is unavailable")
T:eq(listed[1].status, "corrupt_metadata", "corrupt list entry explains status")
T:eq(listed[2].available, true, "older valid list entry remains available")

skipCorrupt.game.current = checkpoint(40)
local explicit, explicitCode, explicitMessage = skipCorrupt.service:loadState(
  skipCorrupt.game, "q00000001")
T:check(explicit ~= nil, "explicit older-state load succeeds: "
  .. tostring(explicitCode or explicitMessage))
T:eq(skipCorrupt.game.current.save.money, 10, "explicit load restores selected id")

local deleted, deleteCode, deleteMessage = skipCorrupt.service:deleteState(
  skipCorrupt.game, "q00000002")
T:check(deleted == true, "corrupt indexed state can be deleted: "
  .. tostring(deleteCode or deleteMessage))
T:eq(#skipCorrupt.storeFactory(skipCorrupt.game):loadIndex():list("quick"), 1,
  "delete removes only selected metadata")
T:eq(skipCorrupt.storage.values["states/q00000002"], nil,
  "delete removes selected corrupt payload")
T:eq(skipCorrupt.notifications[#skipCorrupt.notifications].kind, "state_deleted",
  "delete emits notification")

local allCorrupt = environment({ money = 10 })
T:check(allCorrupt.service:quickSave(allCorrupt.game), "all-corrupt fixture saves")
allCorrupt.storage.values["states/q00000001"].metadata.createdAt = -1
local noValid, noValidCode = allCorrupt.service:quickLoad(allCorrupt.game)
T:eq(noValid, nil, "history with no valid payload cannot load")
T:eq(noValidCode, "no_valid_quick_save", "all-invalid history has distinct error code")

local recoveryCaptureFailure = environment({ money = 100 })
T:check(recoveryCaptureFailure.service:quickSave(recoveryCaptureFailure.game),
  "recovery-capture target saves")
recoveryCaptureFailure.game.current = checkpoint(200)
recoveryCaptureFailure.checkpoints.captureFailure = "capture_failed"
local blockedLoad, blockedLoadCode = recoveryCaptureFailure.service:quickLoad(
  recoveryCaptureFailure.game)
T:eq(blockedLoad, nil, "failed recovery capture blocks load")
T:eq(blockedLoadCode, "capture_failed", "recovery capture error is preserved")
T:eq(recoveryCaptureFailure.game.current.save.money, 200,
  "failed recovery capture leaves runtime untouched")

local recoveryWriteFailure = environment({ money = 100 })
T:check(recoveryWriteFailure.service:quickSave(recoveryWriteFailure.game),
  "recovery-write target saves")
recoveryWriteFailure.game.current = checkpoint(200)
recoveryWriteFailure.storage.failWrite.recovery = true
local unprotectedLoad, unprotectedCode = recoveryWriteFailure.service:quickLoad(
  recoveryWriteFailure.game)
T:eq(unprotectedLoad, nil, "failed durable recovery blocks load")
T:eq(unprotectedCode, "write_failed", "recovery write error is preserved")
T:eq(recoveryWriteFailure.game.current.save.money, 200,
  "failed recovery write leaves runtime untouched")

local restoreFailure = environment({ money = 100 })
T:check(restoreFailure.service:quickSave(restoreFailure.game), "restore-failure target saves")
restoreFailure.game.current = checkpoint(200)
restoreFailure.checkpoints.restoreFailure = "restore_failed"
local unrestored, unrestoredCode = restoreFailure.service:quickLoad(restoreFailure.game)
T:eq(unrestored, nil, "engine restore failure is reported")
T:eq(unrestoredCode, "restore_failed", "engine restore error is preserved")
T:eq(restoreFailure.game.current.save.money, 200,
  "engine restore failure leaves fake runtime unchanged")
T:eq(restoreFailure.storeFactory(restoreFailure.game):loadRecovery().checkpoint.save.money,
  200, "failed restore still leaves durable recovery available")

local undoEmpty = environment()
local noUndo, noUndoCode = undoEmpty.service:undoLastLoad(undoEmpty.game)
T:eq(noUndo, nil, "undo without recovery is rejected")
T:eq(noUndoCode, "no_recovery", "undo without recovery preserves store code")

local undo = environment({ money = 100 })
T:check(undo.service:quickSave(undo.game), "undo target saves")
undo.game.current = checkpoint(200)
T:check(undo.service:quickLoad(undo.game), "undo fixture performs initial load")
T:eq(undo.game.current.save.money, 100, "initial load changes runtime")
local writesBeforeUndo = 0
for _, event in ipairs(undo.events) do
  if event == "write:recovery" then writesBeforeUndo = writesBeforeUndo + 1 end
end
local undone, undoCode, undoMessage = undo.service:undoLastLoad(undo.game)
T:check(undone ~= nil, "undo restores recovery: " .. tostring(undoCode or undoMessage))
T:eq(undo.game.current.save.money, 200, "undo restores exact pre-load progress")
local writesAfterUndo = 0
for _, event in ipairs(undo.events) do
  if event == "write:recovery" then writesAfterUndo = writesAfterUndo + 1 end
end
T:eq(writesAfterUndo, writesBeforeUndo, "undo does not overwrite its recovery target")
T:eq(undo.notifications[#undo.notifications].kind, "load_undone",
  "successful undo emits notification")

local unsafeUndo = environment({ money = 100 })
T:check(unsafeUndo.service:quickSave(unsafeUndo.game), "unsafe-undo target saves")
unsafeUndo.game.current = checkpoint(200)
T:check(unsafeUndo.service:quickLoad(unsafeUndo.game), "unsafe-undo recovery is created")
unsafeUndo.checkpoints.capability = {
  canCapture = false, canRestore = false, kind = "overworld",
  reason = "screen_busy", message = "Close the active screen.",
}
local rejectedUndo, rejectedUndoCode = unsafeUndo.service:undoLastLoad(unsafeUndo.game)
T:eq(rejectedUndo, nil, "unsafe undo is rejected before reading/mutation")
T:eq(rejectedUndoCode, "screen_busy", "unsafe undo preserves capability reason")

T:finish()
