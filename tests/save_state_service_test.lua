local Test = dofile("tests/testlib.lua")
local T = Test.new("save state service")
local DataOnly = dofile("src/util/DataOnly.lua")
local Preview = dofile("src/state/Preview.lua")(DataOnly)
local Snapshot = dofile("src/state/Snapshot.lua")(DataOnly)
local Validator = dofile("src/state/SnapshotValidator.lua")(DataOnly, Preview)
local StateMigrations = dofile("src/state/StateMigrations.lua")(DataOnly)
local StateIndex = dofile("src/state/StateIndex.lua")(DataOnly, Preview)
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
      playTime = 16620,
      inventory = { BOULDERBADGE = true },
      party = {
        { species = "PIKACHU", nickname = "SPARKY", level = 22, hp = 45,
          stats = { hp = 57 }, status = "PAR" },
      },
    },
    runtime = { overworld = {
      map = map, x = 5, y = 6, facing = "down", surfing = false,
    } },
  }
end

local function battleCheckpoint(money, kind)
  local value = checkpoint(money, "PALLET_TOWN")
  value.kind = "battle"
  value.runtime.battle = {
    kind = kind or "wild",
    origin = { kind = (kind == "trainer") and "trainer_encounter"
      or "wild_encounter", map = "PALLET_TOWN" },
    turnCount = 1,
  }
  value.rng = { love = "fixture-battle-rng" }
  return value
end

local function environment(args)
  args = args or {}
  local events = {}
  local game = { current = checkpoint(args.money or 100) }
  local storage = {
    values = {}, failWrite = {}, failRead = {}, failDelete = {}, events = events,
  }
  function storage:context()
    return {
      engineVersion = "0.9.0-dev",
      gameVersion = "red",
      playthroughId = "play-a",
      normalSavedAt = args.normalSavedAt,
    }
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
  function checkpoints:resume(targetGame, target)
    events[#events + 1] = "resume:" .. tostring(target.save.money)
    if self.resumeFailure then
      return false, self.resumeFailure, "injected title resume failure"
    end
    targetGame.current = assert(DataOnly.copy(target))
    return true
  end

  local migrations = StateMigrations.new(1)
  local storeScopes = {}
  local function storeFactory(targetGame, scope)
    storeScopes[#storeScopes + 1] = scope or "active"
    if scope == "selected" then events[#events + 1] = "selected_store" end
    return StateStore.new({
      storage = storage,
      game = targetGame,
      validator = Validator,
      migrations = migrations,
      supportedKinds = { overworld = true, battle = true },
    })
  end
  local notifications = {}
  local debugMetrics = {}
  local warnings, errors = {}, {}
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
    previewFor = function(_, captured)
      return Preview.capture(captured.save, {
        badgeIds = { "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
          "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE" },
        speciesName = function(id) return id end,
      })
    end,
    modVersion = "0.1.0",
    modApi = 2,
    notify = function(kind, detail)
      notifications[#notifications + 1] = { kind = kind, detail = detail }
    end,
    debugEnabled = args.debugEnabled,
    timer = args.timer,
    measureSize = args.measureSize,
    debug = function(metric) debugMetrics[#debugMetrics + 1] = metric end,
    warn = function(code, message, metadata)
      warnings[#warnings + 1] = { code = code, message = message, metadata = metadata }
    end,
    error = function(code, message, metadata)
      errors[#errors + 1] = { code = code, message = message, metadata = metadata }
    end,
  })
  return {
    game = game,
    storage = storage,
    checkpoints = checkpoints,
    service = service,
    notifications = notifications,
    debugMetrics = debugMetrics,
    warnings = warnings,
    errors = errors,
    events = events,
    storeScopes = storeScopes,
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
T:eq(unsafe.warnings[1].code, "script_busy", "unsafe save logs a warning reason")
T:eq(#unsafe.errors, 0, "ordinary capability rejection is not an error log")

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
T:eq(saved.metadata.preview.playTime, 16620,
  "quicksave captures preview play time from checkpoint progress")
T:eq(saved.metadata.preview.badgeCount, 1,
  "quicksave captures checkpoint badge progress")
T:eq(saved.metadata.preview.party[1].name, "SPARKY",
  "quicksave captures nickname preview from checkpoint progress")
T:eq(saved.metadata.preview.party[1].status, nil,
  "quicksave preview does not carry battle status")
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
T:eq(#happy.debugMetrics, 0, "performance logging is silent by default")

happy.storage.values["states/q00000001"].identity.engineVersion = "0.8.0"
happy.storage.values["states/q00000001"].checkpoint.identity.engineVersion = "0.8.0"
for index = #happy.events, 1, -1 do happy.events[index] = nil end
local versionRows = happy.service:listStates(happy.game, "quick")
T:eq(versionRows[1].metadata.preview.party[1].name, "SPARKY",
  "history browsing reads rich capture preview from the index")
T:eq(versionRows[1].available, nil,
  "history browsing does not claim payload compatibility before inspection")
for _, event in ipairs(happy.events) do
  T:check(event ~= "read:states/q00000001",
    "history browsing does not decode its checkpoint payload")
end
local versionDetail, versionDetailCode, versionDetailMessage = happy.service:inspectState(
  happy.game, "q00000001")
T:check(versionDetail ~= nil,
  "opening a selected state inspects its payload: "
    .. tostring(versionDetailCode or versionDetailMessage))
T:eq(versionDetail.available, true,
  "engine-version mismatch remains available after selected-state inspection")
T:eq(versionDetail.warnings[1], "engine_version_mismatch",
  "selected-state inspection exposes engine-version compatibility warning")

local performanceNow = 10
local performance = environment({
  money = 321,
  debugEnabled = function() return true end,
  timer = function()
    performanceNow = performanceNow + 0.002
    return performanceNow
  end,
  measureSize = function() return 4321 end,
})
T:check(performance.service:quickSave(performance.game) ~= nil,
  "instrumented quicksave succeeds")
performance.game.current = checkpoint(999, "ROUTE_1")
T:check(performance.service:quickLoad(performance.game) ~= nil,
  "instrumented quickload succeeds")
local metricNames = {}
for _, metric in ipairs(performance.debugMetrics) do
  metricNames[metric.operation] = metric
  T:check(type(metric.elapsedMs) == "number" and metric.elapsedMs >= 0,
    "performance metric has a nonnegative duration")
end
for _, operation in ipairs({
  "checkpoint_capture", "snapshot_serialize", "state_write",
  "recovery_write", "checkpoint_restore",
}) do
  T:check(metricNames[operation] ~= nil,
    "debug logging measures " .. operation)
end
T:eq(metricNames.snapshot_serialize.bytes, 4321,
  "debug serialization metric reports snapshot size")

local battleStates = environment({ money = 400 })
battleStates.game.current = battleCheckpoint(400, "wild")
battleStates.checkpoints.capability = {
  canCapture = true, canRestore = true, kind = "battle",
}
local battleSaved, battleSaveCode, battleSaveMessage =
  battleStates.service:quickSave(battleStates.game)
T:check(battleSaved ~= nil,
  "battle safe-point quicksave succeeds: "
    .. tostring(battleSaveCode or battleSaveMessage))
T:eq(battleSaved.metadata.stateKind, "battle",
  "battle quicksave records its runtime kind")
T:eq(battleSaved.metadata.preview.party[1].hp, 45,
  "battle checkpoint preview uses captured canonical party values")
battleStates.game.current = checkpoint(900, "ROUTE_1")
battleStates.checkpoints.capability = {
  canCapture = true, canRestore = true, kind = "overworld",
}
local battleLoaded, battleLoadCode, battleLoadMessage =
  battleStates.service:quickLoad(battleStates.game)
T:check(battleLoaded ~= nil,
  "battle safe-point quickload succeeds: "
    .. tostring(battleLoadCode or battleLoadMessage))
T:eq(battleStates.game.current.kind, "battle",
  "quickload forwards opaque battle checkpoint to the engine")
T:eq(battleStates.storeFactory(battleStates.game):loadRecovery().checkpoint.kind,
  "overworld", "battle quickload preserves an overworld undo target")

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
T:eq(listedSlots[3].metadata.label, "SLOT 03", "slot listing exposes saved label")
T:eq(listedSlots[3].available, nil,
  "slot browsing remains index-only until the player opens a slot")

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

slots.setNow(2000)
local renamed, renameCode, renameMessage = slots.service:renameSlot(
  slots.game, 3, "ROUTE ONE")
T:check(renamed ~= nil, "slot rename succeeds: " .. tostring(renameCode or renameMessage))
T:eq(renamed.metadata.label, "ROUTE ONE", "slot rename changes metadata label")
T:eq(renamed.metadata.createdAt, overwritten.metadata.createdAt,
  "slot rename preserves the checkpoint creation time")
T:eq(renamed.checkpoint.save.money, 600, "slot rename preserves checkpoint progress")
T:eq(renamed.metadata.preview.party[1].name,
  overwritten.metadata.preview.party[1].name,
  "slot rename preserves capture preview provenance")
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
slots.setNow(3000)
local pinned, pinCode, pinMessage = slots.service:pinToSlot(
  slots.game, pinnedSource.metadata.id, 4, "PINNED")
T:check(pinned ~= nil, "quick state pins to permanent slot: "
  .. tostring(pinCode or pinMessage))
T:eq(pinned.metadata.slot, 4, "pinned state targets selected slot")
T:eq(pinned.metadata.label, "PINNED", "pinned state stores selected label")
T:eq(pinned.checkpoint.save.money, 600, "pin copies source checkpoint, not live runtime")
T:eq(pinned.metadata.createdAt, pinnedSource.metadata.createdAt,
  "pin preserves the source checkpoint creation time")
T:eq(pinned.metadata.preview.party[1].name, pinnedSource.metadata.preview.party[1].name,
  "pin preserves source capture preview provenance")

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

local autoCaptureFailure = environment()
autoCaptureFailure.checkpoints.captureFailure = "capture_failed"
local failedAuto, failedAutoCode = autoCaptureFailure.service:autoSave(
  autoCaptureFailure.game, "location_enter", {
    mapId = "PALLET_TOWN", contextKey = "PALLET_TOWN",
  })
T:eq(failedAuto, nil, "capture failure aborts autosave")
T:eq(failedAutoCode, "capture_failed", "autosave preserves capture error")
T:eq(autoCaptureFailure.notifications[1]
    and autoCaptureFailure.notifications[1].kind, "save_failed",
  "real autosave capture failure is visible")
T:eq(autoCaptureFailure.errors[1] and autoCaptureFailure.errors[1].code,
  "capture_failed", "real autosave capture failure is error-grade")

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

autos.setNow(201)
local pinnedAuto = autos.service:pinToSlot(autos.game, autoOne.metadata.id, 2)
T:check(pinnedAuto ~= nil, "autosave pins to permanent slot")
T:eq(pinnedAuto.metadata.createdAt, autoOne.metadata.createdAt,
  "pinning autosave preserves source creation time")
T:eq(pinnedAuto.metadata.trigger, autoOne.metadata.trigger,
  "pinning autosave preserves semantic trigger")
T:eq(pinnedAuto.metadata.contextKey, autoOne.metadata.contextKey,
  "pinning autosave preserves semantic context")

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
local staleWarp, staleWarpCode = staleAuto.service:autoSave(staleAuto.game, "before_warp", {
  mapId = "ROUTE_1", contextKey = "ROUTE_1>VIRIDIAN_CITY",
})
T:eq(staleWarp, nil, "mismatched before-warp source never saves another map")
T:eq(staleWarpCode, "stale_trigger", "mismatched warp source has stable code")
T:eq(staleAuto.storage.values.index, nil, "mismatched warp publishes nothing")

local writeFailure = environment()
writeFailure.storage.failWrite["states/q00000001"] = true
local unwritten, unwrittenCode = writeFailure.service:quickSave(writeFailure.game)
T:eq(unwritten, nil, "payload write failure aborts quicksave")
T:eq(unwrittenCode, "write_failed", "payload write failure preserves storage code")
T:eq(writeFailure.storage.values.index, nil, "payload failure publishes no index")
T:eq(writeFailure.errors[1].code, "write_failed",
  "persistence failure emits an error-level diagnostic")

local empty = environment()
local noQuick, noQuickCode = empty.service:quickLoad(empty.game)
T:eq(noQuick, nil, "quickload with empty history is rejected")
T:eq(noQuickCode, "no_quick_save", "empty history has product-level error code")
T:eq(empty.notifications[1].kind, "load_failed", "empty quickload is notified")
T:eq(empty.warnings[1].code, "no_quick_save", "empty quickload is warning-grade")
T:eq(#empty.errors, 0, "empty quickload is not an engine error")

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
T:eq(listed[1].status, "unverified",
  "index-only history does not decode corrupt payloads while browsing")
local corruptDetail = skipCorrupt.service:inspectState(skipCorrupt.game, listed[1].metadata.id)
T:eq(corruptDetail.available, false, "selected corrupt entry is unavailable")
T:eq(corruptDetail.status, "corrupt_metadata",
  "selected corrupt entry explains its payload status")
local validDetail = skipCorrupt.service:inspectState(skipCorrupt.game, listed[2].metadata.id)
T:eq(validDetail.available, true, "older valid selected entry remains available")

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

-- A title session has no live runtime to protect with a recovery snapshot.
-- It must use the engine's separate validated resume transaction and the
-- selected-playthrough storage scope, never ordinary active-game restore.
local titleResume = environment({ money = 100 })
local titleTarget = titleResume.service:quickSave(titleResume.game)
T:check(titleTarget ~= nil, "title-resume fixture has a durable quicksave")
titleResume.game.current = checkpoint(900)
local eventCount = #titleResume.events
T:eq(type(titleResume.service.resumeTitleState), "function",
  "service exposes a distinct title checkpoint resume operation")
if type(titleResume.service.resumeTitleState) == "function" and titleTarget then
  local resumed, resumeCode, resumeMessage = titleResume.service:resumeTitleState(
    titleResume.game, titleTarget.metadata.id)
  T:check(resumed ~= nil,
    "title resume installs a validated selected state: " .. tostring(resumeCode or resumeMessage))
  T:eq(titleResume.game.current.save.money, 100,
    "title resume reconstructs the selected checkpoint progress")
  T:eq(titleResume.events[eventCount + 1], "selected_store",
    "title resume resolves storage through the selected playthrough scope")
  T:eq(titleResume.events[#titleResume.events], "resume:100",
    "title resume uses the engine bootstrap operation instead of live restore")
  for index = eventCount + 1, #titleResume.events do
    T:check(titleResume.events[index] ~= "capture"
        and titleResume.events[index] ~= "write:recovery",
      "title resume never captures a recovery checkpoint")
  end
end
T:eq(type(titleResume.service.titleSummary), "function",
  "title manager exposes a selected-playthrough summary")
T:eq(type(titleResume.service.titleListStates), "function",
  "title manager exposes selected quick and auto history")
T:eq(type(titleResume.service.titleInspectState), "function",
  "title manager inspects selected state payloads")
T:eq(type(titleResume.service.titleListSlots), "function",
  "title manager exposes selected permanent slots")
T:eq(type(titleResume.service.titlePinToSlot), "function",
  "title manager can make a durable slot copy without live capture")
T:eq(type(titleResume.service.titleRenameSlot), "function",
  "title manager can rename a selected permanent slot")
T:eq(type(titleResume.service.titleDeleteState), "function",
  "title manager can delete selected durable state data")
if titleTarget and type(titleResume.service.titleSummary) == "function"
    and type(titleResume.service.titleListStates) == "function"
    and type(titleResume.service.titleInspectState) == "function"
    and type(titleResume.service.titleListSlots) == "function"
    and type(titleResume.service.titlePinToSlot) == "function"
    and type(titleResume.service.titleRenameSlot) == "function"
    and type(titleResume.service.titleDeleteState) == "function" then
  local titleSummary = titleResume.service:titleSummary(titleResume.game)
  T:eq(titleSummary.quickCount, 1, "title summary reads selected quick history")
  T:eq(titleSummary.undoAvailable, false,
    "title summary never presents recovery as an automatic resume choice")
  local titleRows = titleResume.service:titleListStates(titleResume.game, "quick")
  T:eq(titleRows[1].metadata.id, titleTarget.metadata.id,
    "title history exposes the selected quick metadata")
  local titleDetail = titleResume.service:titleInspectState(
    titleResume.game, titleTarget.metadata.id)
  T:eq(titleDetail.available, true, "title inspection validates the selected payload")
  local pinned = titleResume.service:titlePinToSlot(
    titleResume.game, titleTarget.metadata.id, 2)
  T:check(pinned ~= nil, "title pin copies a selected state without live capture")
  T:eq(pinned.metadata.createdAt, titleTarget.metadata.createdAt,
    "title pin preserves original capture chronology")
  local renamed = titleResume.service:titleRenameSlot(titleResume.game, 2, "BEFORE TEST")
  T:check(renamed ~= nil, "title slot rename is a selected durable operation")
  T:eq(renamed.metadata.createdAt, titleTarget.metadata.createdAt,
    "title rename preserves original capture chronology")
  local titleSlots = titleResume.service:titleListSlots(titleResume.game)
  T:eq(titleSlots[2].metadata.label, "BEFORE TEST",
    "title slot list reflects renamed selected metadata")
  T:check(titleResume.service:titleDeleteState(titleResume.game, titleTarget.metadata.id),
    "title delete removes the selected history entry")
  T:eq(#titleResume.service:titleListStates(titleResume.game, "quick"), 0,
    "title delete does not require a live checkpoint runtime")
end

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

local busyLoad = environment({ money = 100 })
T:check(busyLoad.service:quickSave(busyLoad.game), "busy-load target saves")
busyLoad.checkpoints.capability = {
  canCapture = false, canRestore = false, kind = "overworld",
  reason = "script_busy", message = "Wait for the active script to finish.",
}
local refusedLoad, refusedLoadCode = busyLoad.service:quickLoad(busyLoad.game)
T:eq(refusedLoad, nil, "unsafe recovery boundary blocks quickload")
T:eq(refusedLoadCode, "script_busy", "quickload preserves capability refusal")
T:eq(busyLoad.warnings[#busyLoad.warnings]
    and busyLoad.warnings[#busyLoad.warnings].code, "script_busy",
  "load-time capability refusal is warning-grade")
T:eq(#busyLoad.errors, 0, "load-time capability refusal is not an engine error")

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
T:eq(restoreFailure.errors[#restoreFailure.errors].code, "restore_failed",
  "restore failure emits an error-level diagnostic")
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

-- Title CONTINUE policy reads only the engine-selected facade.  It never
-- captures or mutates a normal save; it selects an already validated durable
-- checkpoint only when it is newer than the engine-provided normal-save
-- chronology.
local titleLatest = environment({ money = 100, now = 1000, normalSavedAt = 900 })
local firstLatest = titleLatest.service:quickSave(titleLatest.game)
titleLatest.setNow(1100)
titleLatest.game.current = checkpoint(200)
local secondLatest = titleLatest.service:quickSave(titleLatest.game)
T:eq(type(titleLatest.service.titleLatestResumeCandidate), "function",
  "title latest policy is exposed by the service")
if type(titleLatest.service.titleLatestResumeCandidate) == "function" then
  local newest, newestCode = titleLatest.service:titleLatestResumeCandidate(titleLatest.game)
  T:eq(newestCode, nil, "newer checkpoint is a valid title candidate")
  T:eq(newest and newest.metadata.id, secondLatest and secondLatest.metadata.id,
    "title selects the newest original capture")
  T:eq(titleLatest.events[#titleLatest.events], "read:states/" .. secondLatest.metadata.id,
    "title candidate validation reads only the selected payload")

  titleLatest.storage.values["states/" .. secondLatest.metadata.id] = { malformed = true }
  local fallback, fallbackCode = titleLatest.service:titleLatestResumeCandidate(titleLatest.game)
  T:eq(fallbackCode, nil, "a corrupt newest candidate is skipped")
  T:eq(fallback and fallback.metadata.id, firstLatest and firstLatest.metadata.id,
    "title falls back to the next valid checkpoint")

  local normalNewer = environment({ money = 100, now = 1000, normalSavedAt = 1200 })
  local older = normalNewer.service:quickSave(normalNewer.game)
  local ordinary, ordinaryCode = normalNewer.service:titleLatestResumeCandidate(normalNewer.game)
  T:eq(ordinary, nil, "a newer ordinary save remains the title target")
  T:eq(ordinaryCode, "normal_save_newer",
    "the ordinary-save chronology wins equal-or-newer ties")
  T:check(older ~= nil, "ordinary-save comparison fixture was persisted")
end

T:finish()
