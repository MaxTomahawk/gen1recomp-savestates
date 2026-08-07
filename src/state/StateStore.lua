return function(deps)
  local DataOnly = assert(deps.DataOnly, "StateStore needs DataOnly")
  local StateIndex = assert(deps.StateIndex, "StateStore needs StateIndex")

  local StateStore = {}
  StateStore.__index = StateStore

  local function validId(id)
    return type(id) == "string" and id ~= "" and id:match("^[%w_-]+$") ~= nil
  end

  function StateStore.new(args)
    assert(type(args) == "table" and type(args.storage) == "table",
      "StateStore.new needs public storage")
    assert(type(args.validator) == "table" and type(args.validator.validate) == "function",
      "StateStore.new needs a snapshot validator")
    assert(type(args.migrations) == "table" and type(args.migrations.run) == "function",
      "StateStore.new needs snapshot migrations")
    return setmetatable({
      storage = args.storage,
      game = args.game,
      validator = args.validator,
      migrations = args.migrations,
      supportedKinds = args.supportedKinds or {},
    }, StateStore)
  end

  function StateStore:_context(extra)
    local context, code, message = self.storage:context(self.game)
    if not context then return nil, code, message end
    local detached, dataCode, dataMessage = DataOnly.copy(context)
    if not detached then return nil, dataCode, dataMessage end
    detached.supportedKinds = self.supportedKinds
    for key, value in pairs(extra or {}) do detached[key] = value end
    return detached
  end

  function StateStore:loadIndex()
    local record, code, message = self.storage:read(self.game, "index")
    if not record then
      if code ~= "not_found" then return nil, code, message end
      local keys, listCode, listMessage = self.storage:list(self.game, "index")
      if not keys then return nil, listCode, listMessage end
      for _, key in ipairs(keys) do
        if key == "index" then
          return nil, "bad_index", "Savestate index exists but has no valid generation."
        end
      end
      return StateIndex.new()
    end
    local index = StateIndex.new(record)
    if not index then return nil, "bad_index", "Savestate index is corrupt." end
    return index
  end

  function StateStore:_validate(snapshot, extraContext)
    local context, code, message = self:_context(extraContext)
    if not context then return nil, code, message end
    return self.validator.validate(snapshot, context)
  end

  function StateStore:writeSnapshot(snapshot)
    local validated, code, message = self:_validate(snapshot)
    if not validated then return nil, code, message end
    local id = validated.metadata.id
    if not validId(id) then return nil, "corrupt_metadata", "Snapshot id is invalid." end
    local ok, writeCode, writeMessage = self.storage:write(
      self.game, "states/" .. id, validated)
    if not ok then return nil, writeCode, writeMessage end
    return true
  end

  function StateStore:readSnapshot(id, extraContext)
    if not validId(id) then return nil, "invalid_id", "Snapshot id is invalid." end
    local raw, code, message = self.storage:read(self.game, "states/" .. id)
    if not raw then
      if code == "not_found" then
        return nil, "payload_missing", "Indexed snapshot payload is missing or corrupt."
      end
      return nil, code, message
    end
    local migrated, migrationCode, migrationMessage = self.migrations:run(raw)
    if not migrated then return nil, migrationCode, migrationMessage end
    return self:_validate(migrated, extraContext)
  end

  function StateStore:publish(index)
    if type(index) ~= "table" or type(index.record) ~= "function" then
      return nil, "bad_index", "StateStore.publish needs a StateIndex."
    end
    local record = index:record()
    local checked = StateIndex.new(record)
    if not checked then return nil, "bad_index", "Savestate index is corrupt." end
    local ok, code, message = self.storage:write(self.game, "index", record)
    if not ok then return nil, code, message end
    return true
  end

  function StateStore:delete(index, id)
    if type(index) ~= "table" or type(index.record) ~= "function" then
      return nil, "bad_index", "StateStore.delete needs a StateIndex."
    end
    local working, code, message = StateIndex.new(index:record())
    if not working then return nil, code, message end
    local removed, removeCode, removeMessage = working:remove(id)
    if not removed then return nil, removeCode, removeMessage end

    local published, publishCode, publishMessage = self:publish(working)
    if not published then return nil, publishCode, publishMessage end
    local deleted, deleteCode, deleteMessage = self.storage:delete(
      self.game, "states/" .. id)
    if not deleted and deleteCode ~= "not_found" then
      return working, "orphaned_payload",
        "State was unpublished, but payload cleanup failed: " .. tostring(deleteMessage)
    end
    return working
  end

  function StateStore:saveRecovery(snapshot)
    local validated, code, message = self:_validate(snapshot)
    if not validated then return nil, code, message end
    if validated.metadata.id ~= "recovery"
        or validated.metadata.stateClass ~= "recovery" then
      return nil, "corrupt_metadata", "Recovery snapshot metadata is inconsistent."
    end
    local ok, writeCode, writeMessage = self.storage:write(
      self.game, "recovery", validated)
    if not ok then return nil, writeCode, writeMessage end
    return true
  end

  function StateStore:loadRecovery(extraContext)
    local raw, code, message = self.storage:read(self.game, "recovery")
    if not raw then
      if code == "not_found" then return nil, "no_recovery", "No recovery state exists." end
      return nil, code, message
    end
    local migrated, migrationCode, migrationMessage = self.migrations:run(raw)
    if not migrated then return nil, migrationCode, migrationMessage end
    return self:_validate(migrated, extraContext)
  end

  function StateStore:scanOrphans()
    local index, code, message = self:loadIndex()
    if not index then return nil, code, message end
    local referenced = {}
    for id, metadata in pairs(index:record().records) do
      if metadata.stateClass ~= "recovery" then referenced[id] = true end
    end
    local keys, listCode, listMessage = self.storage:list(self.game, "states")
    if not keys then return nil, listCode, listMessage end
    local out = {}
    for _, key in ipairs(keys) do
      local id = key:match("^states/([%w_-]+)$")
      if id and not referenced[id] then out[#out + 1] = id end
    end
    table.sort(out)
    return out
  end

  return StateStore
end
