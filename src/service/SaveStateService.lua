return function(deps)
  local Snapshot = assert(deps.Snapshot, "SaveStateService needs Snapshot")
  local Retention = assert(deps.Retention, "SaveStateService needs Retention")
  local Fingerprint = assert(deps.Fingerprint, "SaveStateService needs Fingerprint")

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
    return setmetatable({
      checkpoints = args.checkpoints,
      storeFactory = args.storeFactory,
      clock = args.clock,
      quickLimit = args.quickLimit,
      modVersion = args.modVersion,
      modApi = args.modApi,
      notify = args.notify,
      warn = args.warn,
      locationLabel = args.locationLabel or defaultLabel,
    }, Service)
  end

  function Service:_notify(kind, detail)
    if type(self.notify) == "function" then pcall(self.notify, kind, detail or {}) end
  end

  function Service:_warn(code, message, metadata)
    if type(self.warn) == "function" then pcall(self.warn, code, message, metadata) end
  end

  function Service:_failure(kind, code, message, detail)
    detail = detail or {}
    detail.code = code
    detail.message = message
    self:_notify(kind, detail)
    return nil, code, message
  end

  function Service:_store(game)
    local ok, store, code, message = pcall(self.storeFactory, game)
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

  function Service:_snapshot(checkpoint, metadata)
    local runtime = checkpoint and checkpoint.runtime and checkpoint.runtime.overworld
    local mapId = runtime and runtime.map
    local fingerprint, fingerprintCode, fingerprintMessage = Fingerprint.of(checkpoint)
    if not fingerprint then return nil, fingerprintCode, fingerprintMessage end
    return Snapshot.new({
      id = metadata.id,
      modVersion = self.modVersion,
      modApi = self.modApi,
      stateClass = metadata.stateClass,
      trigger = metadata.trigger,
      createdAt = metadata.createdAt,
      label = metadata.label,
      locationId = mapId,
      locationName = self.locationLabel(mapId),
      fingerprint = fingerprint,
      checkpoint = checkpoint,
    })
  end

  function Service:quickSave(game)
    local _, capabilityCode, capabilityMessage = self:_capability(game, "capture")
    if capabilityCode then
      return self:_failure("save_rejected", capabilityCode, capabilityMessage)
    end

    local checkpoint, captureCode, captureMessage = invoke(
      self.checkpoints, "capture", game)
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
    local snapshot, snapshotCode, snapshotMessage = self:_snapshot(checkpoint, {
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

    local committed, commitCode, commitMessage = invoke(
      store, "commitRolling", index, snapshot, removals)
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

  function Service:_captureRecovery(game, store)
    local checkpoint, captureCode, captureMessage = invoke(
      self.checkpoints, "capture", game)
    if not checkpoint then return nil, captureCode, captureMessage end
    local createdAt, clockCode, clockMessage = self:_now()
    if not createdAt then return nil, clockCode, clockMessage end
    local recovery, snapshotCode, snapshotMessage = self:_snapshot(checkpoint, {
      id = "recovery",
      stateClass = "recovery",
      trigger = "before_load",
      createdAt = createdAt,
    })
    if not recovery then return nil, snapshotCode, snapshotMessage end
    local saved, saveCode, saveMessage = invoke(store, "saveRecovery", recovery)
    if not saved then return nil, saveCode, saveMessage end
    local verified, verifyCode, verifyMessage = invoke(
      store, "loadRecovery", { engineVersion = checkpoint.identity.engineVersion })
    if not verified then return nil, verifyCode, verifyMessage end
    return verified
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
    target, targetCode, targetMessage, warnings = invoke(
      store, "readSnapshot", target.metadata.id,
      { engineVersion = recovery.identity.engineVersion })
    if not target then return self:_failure("load_failed", targetCode, targetMessage) end
    local restored, restoreCode, restoreMessage = invoke(
      self.checkpoints, "restore", game, target.checkpoint)
    if not restored then
      return self:_failure("load_failed", restoreCode, restoreMessage,
        { id = target.metadata.id })
    end
    self:_notify("state_loaded", {
      id = target.metadata.id,
      locationName = target.metadata.locationName,
      warnings = warnings,
    })
    return target, nil, nil, warnings
  end

  function Service:undoLastLoad(game)
    local _, capabilityCode, capabilityMessage = self:_capability(game, "restore")
    if capabilityCode then
      return self:_failure("load_failed", capabilityCode, capabilityMessage)
    end
    local current, captureCode, captureMessage = invoke(self.checkpoints, "capture", game)
    if not current then return self:_failure("load_failed", captureCode, captureMessage) end
    local store, storeCode, storeMessage = self:_store(game)
    if not store then return self:_failure("load_failed", storeCode, storeMessage) end
    local recovery, recoveryCode, recoveryMessage, warnings = invoke(
      store, "loadRecovery", { engineVersion = current.identity.engineVersion })
    if not recovery then
      return self:_failure("load_failed", recoveryCode, recoveryMessage)
    end
    local restored, restoreCode, restoreMessage = invoke(
      self.checkpoints, "restore", game, recovery.checkpoint)
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
