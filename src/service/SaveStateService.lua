return function(deps)
  local Snapshot = assert(deps.Snapshot, "SaveStateService needs Snapshot")
  local Retention = assert(deps.Retention, "SaveStateService needs Retention")
  local Fingerprint = assert(deps.Fingerprint, "SaveStateService needs Fingerprint")
  local Deduplicator = assert(deps.Deduplicator, "SaveStateService needs Deduplicator")

  local Service = {}
  Service.__index = Service

  local SKIPPABLE_STATE_ERRORS = {
    bad_format = true,
    corrupt_identity = true,
    corrupt_metadata = true,
    cyclic_data = true,
    data_too_deep = true,
    invalid_number = true,
    invalid_table_key = true,
    migration_failed = true,
    missing_migration = true,
    missing_checkpoint = true,
    not_data_only = true,
    payload_missing = true,
    unsupported_format = true,
    unsupported_runtime_kind = true,
    wrong_game = true,
    wrong_playthrough = true,
  }
  local MAX_FUTURE_CAPTURE_SKEW = 24 * 60 * 60
  local AUTO_TRIGGERS = {
    location_enter = true,
    trainer_battle_start = true,
    wild_battle_start = true,
    battle_end = true,
    before_warp = true,
    script_checkpoint = true,
  }
  local WARNING_FAILURES = {
    animation_busy = true,
    bad_format = true,
    bad_index = true,
    bad_metadata = true,
    battle_origin_unsupported = true,
    battle_phase_busy = true,
    battle_variant_unsupported = true,
    corrupt_identity = true,
    corrupt_metadata = true,
    empty_slot = true,
    invalid_checkpoint = true,
    invalid_class = true,
    invalid_content = true,
    invalid_id = true,
    invalid_label = true,
    invalid_limit = true,
    invalid_map = true,
    invalid_migration = true,
    invalid_position = true,
    invalid_slot = true,
    invalid_trigger = true,
    link_battle_unsupported = true,
    migration_failed = true,
    missing_checkpoint = true,
    missing_migration = true,
    missing_persistent_state = true,
    movement_busy = true,
    no_quick_save = true,
    no_recovery = true,
    no_valid_quick_save = true,
    not_data_only = true,
    not_found = true,
    not_in_playthrough = true,
    not_overworld = true,
    payload_missing = true,
    screen_busy = true,
    script_busy = true,
    transition_busy = true,
    unsupported_format = true,
    unsupported_runtime_kind = true,
    wrong_game = true,
    wrong_playthrough = true,
  }

  local function invoke(object, method, ...)
    if type(object) ~= "table" or type(object[method]) ~= "function" then
      return nil, "api_unavailable", "Required public API is unavailable: " .. method
    end
    local ok, first, second, third, fourth = pcall(object[method], object, ...)
    if not ok then
      return nil, "unexpected_error",
        "Public API call failed unexpectedly (" .. method .. "): " .. tostring(first)
    end
    return first, second, third, fourth
  end

  local function defaultLabel(mapId)
    if type(mapId) ~= "string" or mapId == "" then return nil end
    return (mapId:gsub("_", " "))
  end

  function Service.new(args)
    assert(type(args) == "table", "SaveStateService.new needs arguments")
    assert(type(args.checkpoints) == "table", "SaveStateService needs checkpoints")
    assert(type(args.storeFactory) == "function", "SaveStateService needs storeFactory")
    assert(type(args.clock) == "function", "SaveStateService needs clock")
    assert(type(args.quickLimit) == "function", "SaveStateService needs quickLimit")
    assert(type(args.autoLimit) == "function", "SaveStateService needs autoLimit")
    return setmetatable({
      checkpoints = args.checkpoints,
      storeFactory = args.storeFactory,
      clock = args.clock,
      quickLimit = args.quickLimit,
      autoLimit = args.autoLimit,
      deduplicator = Deduplicator.new(5),
      modVersion = args.modVersion,
      modApi = args.modApi,
      notify = args.notify,
      warn = args.warn,
      error = args.error,
      debugEnabled = args.debugEnabled,
      timer = args.timer,
      measureSize = args.measureSize,
      debug = args.debug,
      locationLabel = args.locationLabel or defaultLabel,
      previewFor = args.previewFor,
    }, Service)
  end

  function Service:_notify(kind, detail)
    if type(self.notify) == "function" then pcall(self.notify, kind, detail or {}) end
  end

  function Service:_warn(code, message, metadata)
    if type(self.warn) == "function" then pcall(self.warn, code, message, metadata) end
  end

  function Service:_error(code, message, metadata)
    if type(self.error) == "function" then pcall(self.error, code, message, metadata) end
  end

  function Service:_debugActive()
    if type(self.debugEnabled) ~= "function" then return false end
    local ok, enabled = pcall(self.debugEnabled)
    return ok and enabled == true
  end

  function Service:_emitMetric(metric)
    if type(self.debug) == "function" then pcall(self.debug, metric) end
  end

  function Service:_measure(operation, callback)
    if not self:_debugActive() or type(self.timer) ~= "function" then
      return callback()
    end
    local startOk, started = pcall(self.timer)
    local results
    local function collect(...)
      results = { n = select("#", ...), ... }
    end
    collect(callback())
    local finishOk, finished = pcall(self.timer)
    if startOk and finishOk and type(started) == "number"
        and type(finished) == "number" and finished >= started then
      self:_emitMetric({
        operation = operation,
        elapsedMs = (finished - started) * 1000,
      })
    end
    return unpack(results, 1, results.n)
  end

  function Service:_measureSnapshot(snapshot)
    if not self:_debugActive() or type(self.timer) ~= "function"
        or type(self.measureSize) ~= "function" then return end
    local startOk, started = pcall(self.timer)
    local sizeOk, bytes = pcall(self.measureSize, snapshot)
    local finishOk, finished = pcall(self.timer)
    if startOk and finishOk and sizeOk and type(bytes) == "number"
        and type(started) == "number" and type(finished) == "number"
        and finished >= started then
      self:_emitMetric({
        operation = "snapshot_serialize",
        elapsedMs = (finished - started) * 1000,
        bytes = bytes,
      })
    end
  end

  function Service:_captureCheckpoint(game)
    return self:_measure("checkpoint_capture", function()
      return invoke(self.checkpoints, "capture", game)
    end)
  end

  function Service:_restoreCheckpoint(game, checkpoint)
    return self:_measure("checkpoint_restore", function()
      return invoke(self.checkpoints, "restore", game, checkpoint)
    end)
  end

  function Service:_failure(kind, code, message, detail)
    detail = detail or {}
    detail.code = code
    detail.message = message
    if kind == "save_rejected" or WARNING_FAILURES[code] then
      self:_warn(code, message, detail)
    else
      self:_error(code, message, detail)
    end
    self:_notify(kind, detail)
    return nil, code, message
  end

  function Service:_store(game, scope)
    local ok, store, code, message = pcall(self.storeFactory, game, scope)
    if not ok then
      return nil, "unexpected_error", "Could not initialize state storage: " .. tostring(store)
    end
    if not store then return nil, code or "storage_unavailable", message end
    return store
  end

  function Service:_now()
    local ok, value = pcall(self.clock)
    if not ok or type(value) ~= "number" or value < 0
        or value ~= value or value == math.huge or value == -math.huge then
      return nil, "clock_failed", "Savestate creation time is unavailable."
    end
    return value
  end

  function Service:_limit()
    local ok, value = pcall(self.quickLimit)
    if not ok or type(value) ~= "number" or value < 1 or value % 1 ~= 0 then
      return nil, "invalid_limit", "Quick Save history limit is invalid."
    end
    return value
  end

  function Service:_capability(game, action)
    local capability, code, message = invoke(self.checkpoints, "inspect", game)
    if not capability then return nil, code, message end
    local allowed = action == "capture" and capability.canCapture
      or action == "restore" and capability.canRestore
    if not allowed then
      return nil, capability.reason or "runtime_unsafe",
        capability.message or "The current runtime cannot be checkpointed safely."
    end
    return capability
  end

  function Service:_snapshot(game, checkpoint, metadata, preservePreview)
    local runtime = checkpoint and checkpoint.runtime and checkpoint.runtime.overworld
    local mapId = runtime and runtime.map
    local fingerprint, fingerprintCode, fingerprintMessage = Fingerprint.of(checkpoint)
    if not fingerprint then return nil, fingerprintCode, fingerprintMessage end
    local preview = preservePreview and metadata.preview or nil
    if not preservePreview and type(self.previewFor) == "function" then
      local ok, value, previewCode, previewMessage = pcall(self.previewFor, game, checkpoint)
      if ok and value ~= nil then
        preview = value
      elseif not ok then
        self:_warn("preview_unavailable", "Could not build checkpoint preview: " .. tostring(value),
          metadata)
      else
        self:_warn(previewCode or "preview_unavailable",
          previewMessage or "Could not build checkpoint preview.", metadata)
      end
    end
    local snapshot, code, message = Snapshot.new({
      id = metadata.id,
      modVersion = self.modVersion,
      modApi = self.modApi,
      stateClass = metadata.stateClass,
      trigger = metadata.trigger,
      createdAt = metadata.createdAt,
      label = metadata.label,
      locationId = mapId,
      locationName = metadata.locationName or self.locationLabel(mapId),
      fingerprint = fingerprint,
      slot = metadata.slot,
      contextKey = metadata.contextKey,
      preview = preview,
      checkpoint = checkpoint,
    })
    if snapshot then self:_measureSnapshot(snapshot) end
    return snapshot, code, message
  end

  local function validSlot(slot)
    return type(slot) == "number" and slot >= 1 and slot <= 10 and slot % 1 == 0
  end

  local function slotLabel(slot, label)
    if label == nil or label == "" then return ("SLOT %02d"):format(slot) end
    if type(label) ~= "string" or #label > 18
        or not label:match("^[%w %._'%-]+$") then
      return nil, "invalid_label",
        "Slot labels may use up to 18 letters, numbers, spaces, apostrophes, dots, or hyphens."
    end
    return label
  end

  function Service:quickSave(game)
    local _, capabilityCode, capabilityMessage = self:_capability(game, "capture")
    if capabilityCode then
      return self:_failure("save_rejected", capabilityCode, capabilityMessage)
    end

    local checkpoint, captureCode, captureMessage = self:_captureCheckpoint(game)
    if not checkpoint then
      return self:_failure("save_failed", captureCode, captureMessage)
    end
    local store, storeCode, storeMessage = self:_store(game)
    if not store then return self:_failure("save_failed", storeCode, storeMessage) end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return self:_failure("save_failed", indexCode, indexMessage) end
    local id, idCode, idMessage = invoke(index, "allocate", "quick")
    if not id then return self:_failure("save_failed", idCode, idMessage) end
    local createdAt, clockCode, clockMessage = self:_now()
    if not createdAt then return self:_failure("save_failed", clockCode, clockMessage) end
    local snapshot, snapshotCode, snapshotMessage = self:_snapshot(game, checkpoint, {
      id = id,
      stateClass = "quick",
      trigger = "manual",
      createdAt = createdAt,
    })
    if not snapshot then
      return self:_failure("save_failed", snapshotCode, snapshotMessage)
    end
    local added, addCode, addMessage = invoke(index, "add", "quick", snapshot.metadata)
    if not added then return self:_failure("save_failed", addCode, addMessage) end
    local limit, limitCode, limitMessage = self:_limit()
    if not limit then return self:_failure("save_failed", limitCode, limitMessage) end
    local removals, retentionCode, retentionMessage = Retention.selectRemovals(
      index:list("quick"), limit)
    if not removals then
      return self:_failure("save_failed", retentionCode, retentionMessage)
    end
    for _, removeId in ipairs(removals) do
      local removed, removeCode, removeMessage = invoke(index, "remove", removeId)
      if not removed then return self:_failure("save_failed", removeCode, removeMessage) end
    end

    local committed, commitCode, commitMessage = self:_measure("state_write", function()
      return invoke(store, "commitRolling", index, snapshot, removals)
    end)
    if not committed then
      return self:_failure("save_failed", commitCode, commitMessage)
    end
    if commitCode then self:_warn(commitCode, commitMessage, snapshot.metadata) end
    self:_notify("quick_saved", {
      id = id,
      count = #index:list("quick"),
      limit = limit,
      locationName = snapshot.metadata.locationName,
      warning = commitCode,
    })
    return snapshot, commitCode, commitMessage
  end

  function Service:_autoLimit()
    local ok, value = pcall(self.autoLimit)
    if not ok or type(value) ~= "number" or value < 1 or value % 1 ~= 0 then
      return nil, "invalid_limit", "Auto Save history limit is invalid."
    end
    return value
  end

  function Service:autoSave(game, trigger, context)
    context = type(context) == "table" and context or {}
    if not AUTO_TRIGGERS[trigger] then
      return nil, "invalid_trigger", "Autosave trigger is not supported."
    end
    local _, capabilityCode, capabilityMessage = self:_capability(game, "capture")
    if capabilityCode then return nil, capabilityCode, capabilityMessage end
    local checkpoint, captureCode, captureMessage = self:_captureCheckpoint(game)
    if not checkpoint then
      return self:_failure("save_failed", captureCode, captureMessage)
    end
    local runtime = checkpoint.runtime and checkpoint.runtime.overworld
    local mapId = runtime and runtime.map
    if (trigger == "location_enter" or trigger == "before_warp")
        and context.mapId and context.mapId ~= mapId then
      return nil, "stale_trigger",
        "Autosave event no longer matches the active source map."
    end
    local createdAt, clockCode, clockMessage = self:_now()
    if not createdAt then return self:_failure("save_failed", clockCode, clockMessage) end
    local fingerprint, fingerprintCode, fingerprintMessage = Fingerprint.of(checkpoint)
    if not fingerprint then
      return self:_failure("save_failed", fingerprintCode, fingerprintMessage)
    end
    local store, storeCode, storeMessage = self:_store(game)
    if not store then return self:_failure("save_failed", storeCode, storeMessage) end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return self:_failure("save_failed", indexCode, indexMessage) end
    local newest = index:list("auto")[1]
    local draft = {
      trigger = trigger,
      createdAt = createdAt,
      locationId = mapId,
      contextKey = context.contextKey or context.mapId or mapId,
      fingerprint = fingerprint,
    }
    local decision = self.deduplicator:decide(draft, newest, createdAt)
    if decision == "skip" then return false, "deduplicated", "Autosave cooldown active." end

    local id, idCode, idMessage = invoke(index, "allocate", "auto")
    if not id then return self:_failure("save_failed", idCode, idMessage) end
    local snapshot, snapshotCode, snapshotMessage = self:_snapshot(game, checkpoint, {
      id = id,
      stateClass = "auto",
      trigger = trigger,
      createdAt = createdAt,
      locationName = context.locationName,
      contextKey = draft.contextKey,
    })
    if not snapshot then
      return self:_failure("save_failed", snapshotCode, snapshotMessage)
    end
    local added, addCode, addMessage = invoke(index, "add", "auto", snapshot.metadata)
    if not added then return self:_failure("save_failed", addCode, addMessage) end

    local cleanup, cleanupSet = {}, {}
    local function remove(idToRemove)
      if not idToRemove or cleanupSet[idToRemove] then return true end
      local removed, removeCode, removeMessage = invoke(index, "remove", idToRemove)
      if not removed then return nil, removeCode, removeMessage end
      cleanupSet[idToRemove] = true
      cleanup[#cleanup + 1] = idToRemove
      return true
    end
    if decision == "replace" and newest then
      local removed, removeCode, removeMessage = remove(newest.id)
      if not removed then return self:_failure("save_failed", removeCode, removeMessage) end
    end
    local limit, limitCode, limitMessage = self:_autoLimit()
    if not limit then return self:_failure("save_failed", limitCode, limitMessage) end
    local removals, retentionCode, retentionMessage = Retention.selectRemovals(
      index:list("auto"), limit)
    if not removals then
      return self:_failure("save_failed", retentionCode, retentionMessage)
    end
    for _, removeId in ipairs(removals) do
      local removed, removeCode, removeMessage = remove(removeId)
      if not removed then return self:_failure("save_failed", removeCode, removeMessage) end
    end
    local committed, commitCode, commitMessage = self:_measure("state_write", function()
      return invoke(store, "commitRolling", index, snapshot, cleanup)
    end)
    if not committed then
      return self:_failure("save_failed", commitCode, commitMessage)
    end
    if commitCode then self:_warn(commitCode, commitMessage, snapshot.metadata) end
    self:_notify("auto_saved", {
      id = id,
      trigger = trigger,
      count = #index:list("auto"),
      limit = limit,
      locationName = snapshot.metadata.locationName,
      warning = commitCode,
    })
    return snapshot, commitCode, commitMessage
  end

  function Service:_writeSlot(game, store, index, checkpoint, slot, label, sourceMetadata)
    if not validSlot(slot) then
      return nil, "invalid_slot", "Permanent slot must be an integer from 1 through 10."
    end
    local checkedLabel, labelCode, labelMessage = slotLabel(slot, label)
    if not checkedLabel then return nil, labelCode, labelMessage end
    local previous = index:slot(slot)
    local id, idCode, idMessage = invoke(index, "allocate", "slot", slot)
    if not id then return nil, idCode, idMessage end
    sourceMetadata = type(sourceMetadata) == "table" and sourceMetadata or nil
    local createdAt = sourceMetadata and sourceMetadata.createdAt
    if createdAt == nil then
      local clockCode, clockMessage
      createdAt, clockCode, clockMessage = self:_now()
      if not createdAt then return nil, clockCode, clockMessage end
    end
    local snapshot, snapshotCode, snapshotMessage = self:_snapshot(game, checkpoint, {
      id = id,
      stateClass = "slot",
      slot = slot,
      trigger = sourceMetadata and sourceMetadata.trigger or "manual",
      createdAt = createdAt,
      label = checkedLabel,
      locationName = sourceMetadata and sourceMetadata.locationName,
      contextKey = sourceMetadata and sourceMetadata.contextKey,
      preview = sourceMetadata and sourceMetadata.preview,
    }, sourceMetadata ~= nil)
    if not snapshot then return nil, snapshotCode, snapshotMessage end
    local assigned, assignCode, assignMessage = invoke(
      index, "setSlot", slot, snapshot.metadata)
    if not assigned then return nil, assignCode, assignMessage end
    local cleanup = previous and { previous.id } or {}
    local committed, commitCode, commitMessage = self:_measure("state_write", function()
      return invoke(store, "commitSlot", index, snapshot, cleanup)
    end)
    if not committed then return nil, commitCode, commitMessage end
    if commitCode then self:_warn(commitCode, commitMessage, snapshot.metadata) end
    self:_notify("slot_saved", {
      id = id,
      slot = slot,
      label = checkedLabel,
      locationName = snapshot.metadata.locationName,
      warning = commitCode,
    })
    return snapshot, commitCode, commitMessage
  end

  function Service:saveSlot(game, slot, label)
    if not validSlot(slot) then
      return self:_failure("save_failed", "invalid_slot",
        "Permanent slot must be an integer from 1 through 10.")
    end
    local _, capabilityCode, capabilityMessage = self:_capability(game, "capture")
    if capabilityCode then
      return self:_failure("save_rejected", capabilityCode, capabilityMessage)
    end
    local checkpoint, captureCode, captureMessage = self:_captureCheckpoint(game)
    if not checkpoint then return self:_failure("save_failed", captureCode, captureMessage) end
    local store, storeCode, storeMessage = self:_store(game)
    if not store then return self:_failure("save_failed", storeCode, storeMessage) end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return self:_failure("save_failed", indexCode, indexMessage) end
    local snapshot, code, message = self:_writeSlot(game, store, index, checkpoint, slot, label)
    if not snapshot then return self:_failure("save_failed", code, message) end
    return snapshot, code, message
  end

  function Service:_pinToSlot(game, sourceId, slot, label, scope)
    if not validSlot(slot) then
      return self:_failure("save_failed", "invalid_slot",
        "Permanent slot must be an integer from 1 through 10.")
    end
    local store, storeCode, storeMessage = self:_store(game, scope)
    if not store then return self:_failure("save_failed", storeCode, storeMessage) end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return self:_failure("save_failed", indexCode, indexMessage) end
    if not index:get(sourceId) then
      return self:_failure("save_failed", "not_found", "Source savestate is not indexed.")
    end
    local source, sourceCode, sourceMessage = invoke(store, "readSnapshot", sourceId)
    if not source then return self:_failure("save_failed", sourceCode, sourceMessage) end
    local snapshot, code, message = self:_writeSlot(
      game, store, index, source.checkpoint, slot, label, source.metadata)
    if not snapshot then return self:_failure("save_failed", code, message) end
    return snapshot, code, message
  end

  function Service:pinToSlot(game, sourceId, slot, label)
    return self:_pinToSlot(game, sourceId, slot, label)
  end

  function Service:titlePinToSlot(game, sourceId, slot, label)
    return self:_pinToSlot(game, sourceId, slot, label, "selected")
  end

  function Service:_renameSlot(game, slot, label, scope)
    if not validSlot(slot) then
      return self:_failure("save_failed", "invalid_slot",
        "Permanent slot must be an integer from 1 through 10.")
    end
    local checkedLabel, labelCode, labelMessage = slotLabel(slot, label)
    if not checkedLabel then return self:_failure("save_failed", labelCode, labelMessage) end
    local store, storeCode, storeMessage = self:_store(game, scope)
    if not store then return self:_failure("save_failed", storeCode, storeMessage) end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return self:_failure("save_failed", indexCode, indexMessage) end
    local current = index:slot(slot)
    if not current then
      return self:_failure("save_failed", "empty_slot", "Permanent slot is empty.")
    end
    local source, sourceCode, sourceMessage = invoke(store, "readSnapshot", current.id)
    if not source then return self:_failure("save_failed", sourceCode, sourceMessage) end
    local snapshot, code, message = self:_writeSlot(
      game, store, index, source.checkpoint, slot, checkedLabel, source.metadata)
    if not snapshot then return self:_failure("save_failed", code, message) end
    return snapshot, code, message
  end

  function Service:renameSlot(game, slot, label)
    return self:_renameSlot(game, slot, label)
  end

  function Service:titleRenameSlot(game, slot, label)
    return self:_renameSlot(game, slot, label, "selected")
  end

  function Service:_listSlots(game, scope)
    local store, storeCode, storeMessage = self:_store(game, scope)
    if not store then return nil, storeCode, storeMessage end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return nil, indexCode, indexMessage end
    local rows = {}
    for slot = 1, 10 do
      local metadata = index:slot(slot)
      local row = { slot = slot, occupied = metadata ~= nil, metadata = metadata }
      if metadata then
        row.status = "unverified"
      end
      rows[slot] = row
    end
    return rows
  end

  function Service:listSlots(game)
    return self:_listSlots(game)
  end

  function Service:titleListSlots(game)
    return self:_listSlots(game, "selected")
  end

  function Service:loadSlot(game, slot)
    if not validSlot(slot) then
      return self:_failure("load_failed", "invalid_slot",
        "Permanent slot must be an integer from 1 through 10.")
    end
    local store, storeCode, storeMessage = self:_store(game)
    if not store then return self:_failure("load_failed", storeCode, storeMessage) end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return self:_failure("load_failed", indexCode, indexMessage) end
    local metadata = index:slot(slot)
    if not metadata then
      return self:_failure("load_failed", "empty_slot", "Permanent slot is empty.")
    end
    return self:loadState(game, metadata.id)
  end

  function Service:deleteSlot(game, slot)
    if not validSlot(slot) then
      return self:_failure("save_failed", "invalid_slot",
        "Permanent slot must be an integer from 1 through 10.")
    end
    local store, storeCode, storeMessage = self:_store(game)
    if not store then return self:_failure("save_failed", storeCode, storeMessage) end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return self:_failure("save_failed", indexCode, indexMessage) end
    local metadata = index:slot(slot)
    if not metadata then
      return self:_failure("save_failed", "empty_slot", "Permanent slot is empty.")
    end
    return self:deleteState(game, metadata.id)
  end

  function Service:_newestValidQuick(store, entries)
    for _, metadata in ipairs(entries) do
      local snapshot, code, message, warnings = invoke(
        store, "readSnapshot", metadata.id)
      if snapshot then return snapshot, warnings end
      if not SKIPPABLE_STATE_ERRORS[code] then return nil, nil, code, message end
      self:_warn(code, message, metadata)
    end
    return nil, nil, "no_valid_quick_save",
      "No valid Quick Save is available in this history."
  end

  function Service:_summary(game, scope)
    local store, storeCode, storeMessage = self:_store(game, scope)
    if not store then return nil, storeCode, storeMessage end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return nil, indexCode, indexMessage end
    local record = index:record()
    local slotCount = 0
    for _ in pairs(record.slots or {}) do slotCount = slotCount + 1 end
    local recovery, recoveryCode, recoveryMessage
    if scope ~= "selected" then
      recovery, recoveryCode, recoveryMessage = invoke(store, "loadRecovery")
      if not recovery and recoveryCode ~= "no_recovery" then
        self:_warn(recoveryCode, recoveryMessage, { id = "recovery" })
      end
    end
    return {
      quickCount = #index:list("quick"),
      autoCount = #index:list("auto"),
      slotCount = slotCount,
      slotCapacity = 10,
      undoAvailable = recovery ~= nil,
      recoveryStatus = recovery and "available" or recoveryCode,
    }
  end

  function Service:summary(game)
    return self:_summary(game)
  end

  function Service:titleSummary(game)
    return self:_summary(game, "selected")
  end

  local function validTimestamp(value)
    return type(value) == "number" and value >= 0 and value == value
      and value ~= math.huge and value ~= -math.huge
  end

  function Service:_titleCandidates(index)
    local entries = {}
    for _, class in ipairs({ "quick", "auto" }) do
      for _, metadata in ipairs(index:list(class)) do entries[#entries + 1] = metadata end
    end
    for slot = 1, 10 do
      local metadata = index:slot(slot)
      if metadata then entries[#entries + 1] = metadata end
    end
    table.sort(entries, function(left, right)
      if left.createdAt ~= right.createdAt then return left.createdAt > right.createdAt end
      return left.id < right.id
    end)
    return entries
  end

  -- Select a durable, independently validated automatic title-resume target.
  -- Recovery intentionally never enters the index candidate set.  A normal
  -- save wins an exact timestamp tie: it is the native title behavior and is
  -- the least surprising choice if the host clock has only second precision.
  function Service:titleLatestResumeCandidate(game)
    local store, storeCode, storeMessage = self:_store(game, "selected")
    if not store then return nil, storeCode, storeMessage end
    local context, contextCode, contextMessage = invoke(store, "context")
    if not context then return nil, contextCode, contextMessage end
    local now, nowCode, nowMessage = self:_now()
    if not now then return nil, nowCode, nowMessage end
    local normalSavedAt = context.normalSavedAt
    if not validTimestamp(normalSavedAt) or normalSavedAt > now + MAX_FUTURE_CAPTURE_SKEW then
      normalSavedAt = nil
    end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return nil, indexCode, indexMessage end
    local skipped = false
    for _, metadata in ipairs(self:_titleCandidates(index)) do
      if not validTimestamp(metadata.createdAt)
          or metadata.createdAt > now + MAX_FUTURE_CAPTURE_SKEW then
        skipped = true
        self:_warn("invalid_capture_time",
          "Savestate capture time is invalid or implausibly far in the future.", metadata)
      elseif normalSavedAt ~= nil and metadata.createdAt <= normalSavedAt then
        return nil, "normal_save_newer",
          "The ordinary save is as recent as the newest compatible savestate."
      else
        local snapshot, code, message = invoke(store, "readSnapshot", metadata.id)
        if snapshot then return snapshot end
        if not SKIPPABLE_STATE_ERRORS[code] then return nil, code, message end
        skipped = true
        self:_warn(code, message, metadata)
      end
    end
    if skipped then
      return nil, "no_valid_resume_state", "No valid savestate is available for CONTINUE."
    end
    return nil, "no_resume_state", "No savestate is available for CONTINUE."
  end

  function Service:_listStates(game, class, scope)
    if class ~= "quick" and class ~= "auto" then
      return nil, "invalid_class", "Only rolling state histories can be listed."
    end
    local store, storeCode, storeMessage = self:_store(game, scope)
    if not store then return nil, storeCode, storeMessage end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return nil, indexCode, indexMessage end
    local rows = {}
    for _, metadata in ipairs(index:list(class)) do
      rows[#rows + 1] = {
        metadata = metadata,
        status = "unverified",
      }
    end
    return rows
  end

  function Service:listStates(game, class)
    return self:_listStates(game, class)
  end

  function Service:titleListStates(game, class)
    return self:_listStates(game, class, "selected")
  end

  function Service:_inspectState(game, id, scope)
    local store, storeCode, storeMessage = self:_store(game, scope)
    if not store then return nil, storeCode, storeMessage end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return nil, indexCode, indexMessage end
    local metadata = index:get(id)
    if not metadata then
      return nil, "not_found", "Savestate is not indexed."
    end
    local snapshot, code, message, warnings = invoke(store, "readSnapshot", id)
    return {
      metadata = metadata,
      available = snapshot ~= nil,
      status = snapshot and "compatible" or code,
      message = message,
      warnings = warnings,
      preview = snapshot and snapshot.metadata.preview or metadata.preview,
    }
  end

  function Service:inspectState(game, id)
    return self:_inspectState(game, id)
  end

  function Service:titleInspectState(game, id)
    return self:_inspectState(game, id, "selected")
  end

  function Service:_captureRecovery(game, store)
    local checkpoint, captureCode, captureMessage = self:_captureCheckpoint(game)
    if not checkpoint then return nil, captureCode, captureMessage end
    local createdAt, clockCode, clockMessage = self:_now()
    if not createdAt then return nil, clockCode, clockMessage end
    local recovery, snapshotCode, snapshotMessage = self:_snapshot(game, checkpoint, {
      id = "recovery",
      stateClass = "recovery",
      trigger = "before_load",
      createdAt = createdAt,
    })
    if not recovery then return nil, snapshotCode, snapshotMessage end
    local saved, saveCode, saveMessage = self:_measure("recovery_write", function()
      return invoke(store, "saveRecovery", recovery)
    end)
    if not saved then return nil, saveCode, saveMessage end
    local verified, verifyCode, verifyMessage = invoke(
      store, "loadRecovery", { engineVersion = checkpoint.identity.engineVersion })
    if not verified then return nil, verifyCode, verifyMessage end
    return verified
  end

  function Service:_restoreTarget(game, store, target, warnings)
    local _, capabilityCode, capabilityMessage = self:_capability(game, "restore")
    if capabilityCode then
      return self:_failure("load_failed", capabilityCode, capabilityMessage)
    end
    local recovery, recoveryCode, recoveryMessage = self:_captureRecovery(game, store)
    if not recovery then
      return self:_failure("load_failed", recoveryCode, recoveryMessage)
    end

    -- Re-read after durable recovery so compatibility warnings use the current
    -- engine identity and no state can change between validation and restore.
    local current, targetCode, targetMessage, currentWarnings = invoke(
      store, "readSnapshot", target.metadata.id,
      { engineVersion = recovery.identity.engineVersion })
    if not current then return self:_failure("load_failed", targetCode, targetMessage) end
    warnings = currentWarnings or warnings
    local restored, restoreCode, restoreMessage = self:_restoreCheckpoint(
      game, current.checkpoint)
    if not restored then
      return self:_failure("load_failed", restoreCode, restoreMessage,
        { id = current.metadata.id })
    end
    self:_notify("state_loaded", {
      id = current.metadata.id,
      locationName = current.metadata.locationName,
      warnings = warnings,
    })
    return current, nil, nil, warnings
  end

  function Service:loadState(game, id)
    local store, storeCode, storeMessage = self:_store(game)
    if not store then return self:_failure("load_failed", storeCode, storeMessage) end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return self:_failure("load_failed", indexCode, indexMessage) end
    if not index:get(id) then
      return self:_failure("load_failed", "not_found", "Savestate is not indexed.")
    end
    local target, targetCode, targetMessage, warnings = invoke(
      store, "readSnapshot", id)
    if not target then return self:_failure("load_failed", targetCode, targetMessage) end
    return self:_restoreTarget(game, store, target, warnings)
  end

  -- Title has no live gameplay runtime from which a recovery checkpoint can
  -- be captured. The engine-owned resume transaction validates and rebuilds
  -- the selected checkpoint instead. Its separate selected scope is crucial:
  -- resolving title history must never bind the fresh title skeleton as a New
  -- Game playthrough.
  function Service:resumeTitleState(game, id)
    local store, storeCode, storeMessage = self:_store(game, "selected")
    if not store then return self:_failure("load_failed", storeCode, storeMessage) end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return self:_failure("load_failed", indexCode, indexMessage) end
    if not index:get(id) then
      return self:_failure("load_failed", "not_found", "Savestate is not indexed.")
    end
    local target, targetCode, targetMessage, warnings = invoke(store, "readSnapshot", id)
    if not target then return self:_failure("load_failed", targetCode, targetMessage) end
    local resumed, resumeCode, resumeMessage = invoke(
      self.checkpoints, "resume", game, target.checkpoint)
    if not resumed then
      return self:_failure("load_failed", resumeCode, resumeMessage,
        { id = target.metadata.id })
    end
    self:_notify("state_loaded", {
      id = target.metadata.id,
      locationName = target.metadata.locationName,
      warnings = warnings,
    })
    return target, nil, nil, warnings
  end

  function Service:_deleteState(game, id, scope)
    local store, storeCode, storeMessage = self:_store(game, scope)
    if not store then return self:_failure("save_failed", storeCode, storeMessage) end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return self:_failure("save_failed", indexCode, indexMessage) end
    local metadata = index:get(id)
    if not metadata then
      return self:_failure("save_failed", "not_found", "Savestate is not indexed.")
    end
    local updated, deleteCode, deleteMessage = invoke(store, "delete", index, id)
    if not updated then return self:_failure("save_failed", deleteCode, deleteMessage) end
    if deleteCode then self:_warn(deleteCode, deleteMessage, metadata) end
    self:_notify("state_deleted", { id = id, warning = deleteCode })
    return true, deleteCode, deleteMessage
  end

  function Service:deleteState(game, id)
    return self:_deleteState(game, id)
  end

  function Service:titleDeleteState(game, id)
    return self:_deleteState(game, id, "selected")
  end

  function Service:quickLoad(game)
    local store, storeCode, storeMessage = self:_store(game)
    if not store then return self:_failure("load_failed", storeCode, storeMessage) end
    local index, indexCode, indexMessage = invoke(store, "loadIndex")
    if not index then return self:_failure("load_failed", indexCode, indexMessage) end
    local entries = index:list("quick")
    if #entries == 0 then
      return self:_failure("load_failed", "no_quick_save", "No Quick Save exists.")
    end
    local target, warnings, targetCode, targetMessage = self:_newestValidQuick(
      store, entries)
    if not target then return self:_failure("load_failed", targetCode, targetMessage) end

    return self:_restoreTarget(game, store, target, warnings)
  end

  function Service:undoLastLoad(game)
    local _, capabilityCode, capabilityMessage = self:_capability(game, "restore")
    if capabilityCode then
      return self:_failure("load_failed", capabilityCode, capabilityMessage)
    end
    local current, captureCode, captureMessage = self:_captureCheckpoint(game)
    if not current then return self:_failure("load_failed", captureCode, captureMessage) end
    local store, storeCode, storeMessage = self:_store(game)
    if not store then return self:_failure("load_failed", storeCode, storeMessage) end
    local recovery, recoveryCode, recoveryMessage, warnings = invoke(
      store, "loadRecovery", { engineVersion = current.identity.engineVersion })
    if not recovery then
      return self:_failure("load_failed", recoveryCode, recoveryMessage)
    end
    local restored, restoreCode, restoreMessage = self:_restoreCheckpoint(
      game, recovery.checkpoint)
    if not restored then
      return self:_failure("load_failed", restoreCode, restoreMessage)
    end
    self:_notify("load_undone", {
      locationName = recovery.metadata.locationName,
      warnings = warnings,
    })
    return recovery, nil, nil, warnings
  end

  return Service
end
