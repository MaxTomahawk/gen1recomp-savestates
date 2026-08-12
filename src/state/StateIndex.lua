return function(DataOnly, Preview)
  local StateIndex = {}
  StateIndex.__index = StateIndex

  local CLASSES = { quick = true, auto = true, slot = true, recovery = true }

  local function blank()
    return {
      format = 1,
      sequence = 0,
      records = {},
      quick = {},
      auto = {},
      slots = {},
    }
  end

  local function copy(value)
    local result = DataOnly.copy(value)
    return result
  end

  local function metadataOk(id, metadata, expectedClass)
    if type(id) ~= "string" or id == "" or type(metadata) ~= "table"
        or not CLASSES[metadata.stateClass]
        or (expectedClass ~= nil and metadata.stateClass ~= expectedClass)
        or type(metadata.createdAt) ~= "number" or metadata.createdAt < 0 then
      return false
    end
    if metadata.preview ~= nil then
      if not Preview then return false end
      local preview = Preview.validate(metadata.preview)
      if not preview then return false end
      metadata.preview = preview
    end
    return metadata.id == id
  end

  local function denseList(list)
    if type(list) ~= "table" then return false end
    local count = 0
    for key in pairs(list) do
      if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
      count = count + 1
    end
    return count == #list
  end

  local function validate(record)
    local data = copy(record)
    if type(data) ~= "table" or data.format ~= 1
        or type(data.sequence) ~= "number" or data.sequence < 0
        or data.sequence % 1 ~= 0 or type(data.records) ~= "table"
        or not denseList(data.quick) or not denseList(data.auto)
        or type(data.slots) ~= "table" then
      return nil
    end

    for id, metadata in pairs(data.records) do
      if not metadataOk(id, metadata) then return nil end
    end

    local referenced = {}
    for _, class in ipairs({ "quick", "auto" }) do
      for _, id in ipairs(data[class]) do
        if referenced[id] or not metadataOk(id, data.records[id], class) then return nil end
        referenced[id] = true
      end
    end
    for slot, id in pairs(data.slots) do
      if type(slot) ~= "number" or slot < 1 or slot > 10 or slot % 1 ~= 0
          or type(id) ~= "string" or referenced[id]
          or not metadataOk(id, data.records[id], "slot")
          or data.records[id].slot ~= slot then
        return nil
      end
      referenced[id] = true
    end
    if data.recovery ~= nil then
      if data.recovery ~= "recovery" or referenced.recovery
          or not metadataOk("recovery", data.records.recovery, "recovery") then
        return nil
      end
      referenced.recovery = true
    end
    for id in pairs(data.records) do
      if not referenced[id] then return nil end
    end
    return data
  end

  function StateIndex.new(record)
    local data = validate(record or blank())
    if not data then return nil, "bad_index", "Savestate index is corrupt." end
    return setmetatable({ data = data }, StateIndex)
  end

  function StateIndex:allocate(class, slot)
    local prefix = class == "quick" and "q" or (class == "auto" and "a" or nil)
    if class == "slot" then
      if type(slot) ~= "number" or slot < 1 or slot > 10 or slot % 1 ~= 0 then
        return nil, "invalid_slot", "Permanent slot must be an integer from 1 through 10."
      end
      prefix = ("s%02d_"):format(slot)
    end
    if not prefix then
      return nil, "invalid_class", "Only quick, auto, and slot states allocate ids."
    end
    self.data.sequence = self.data.sequence + 1
    return ("%s%08d"):format(prefix, self.data.sequence)
  end

  local function removeFrom(list, id)
    for i = #list, 1, -1 do
      if list[i] == id then table.remove(list, i) end
    end
  end

  function StateIndex:add(class, metadata)
    if class ~= "quick" and class ~= "auto" then
      return nil, "invalid_class", "Only quick and auto states belong to rolling histories."
    end
    local detached = copy(metadata)
    local id = detached and detached.id
    if not metadataOk(id, detached, class) then
      return nil, "bad_metadata", "State metadata does not match its history."
    end
    local existing = self.data.records[id]
    if existing and existing.stateClass ~= class then
      return nil, "bad_metadata", "State id is already used by another class."
    end
    removeFrom(self.data[class], id)
    table.insert(self.data[class], 1, id)
    self.data.records[id] = detached
    return true
  end

  function StateIndex:replace(id, metadata)
    local existing = self.data.records[id]
    local detached = copy(metadata)
    if not existing then return nil, "not_found", "State metadata does not exist." end
    if not metadataOk(id, detached, existing.stateClass) then
      return nil, "bad_metadata", "Replacement metadata is inconsistent."
    end
    self.data.records[id] = detached
    return true
  end

  function StateIndex:remove(id)
    if not self.data.records[id] then return nil, "not_found", "State metadata does not exist." end
    self.data.records[id] = nil
    removeFrom(self.data.quick, id)
    removeFrom(self.data.auto, id)
    for slot, slotId in pairs(self.data.slots) do
      if slotId == id then self.data.slots[slot] = nil end
    end
    if self.data.recovery == id then self.data.recovery = nil end
    return true
  end

  function StateIndex:get(id)
    return self.data.records[id] and copy(self.data.records[id]) or nil
  end

  function StateIndex:list(class)
    local ids = self.data[class]
    if class ~= "quick" and class ~= "auto" then return {} end
    local out = {}
    for _, id in ipairs(ids) do out[#out + 1] = copy(self.data.records[id]) end
    return out
  end

  function StateIndex:setSlot(slot, metadata)
    if type(slot) ~= "number" or slot < 1 or slot > 10 or slot % 1 ~= 0 then
      return nil, "invalid_slot", "Permanent slot must be an integer from 1 through 10."
    end
    if metadata == nil then
      local id = self.data.slots[slot]
      self.data.slots[slot] = nil
      if id then self.data.records[id] = nil end
      return true
    end
    local detached = copy(metadata)
    local id = detached and detached.id
    if not metadataOk(id, detached, "slot") or detached.slot ~= slot then
      return nil, "bad_metadata", "Slot metadata must identify its slot generation."
    end
    for otherSlot, otherId in pairs(self.data.slots) do
      if otherSlot ~= slot and otherId == id then
        return nil, "bad_metadata", "Slot generation is already used by another slot."
      end
    end
    local previous = self.data.slots[slot]
    if previous and previous ~= id then self.data.records[previous] = nil end
    self.data.records[id] = detached
    self.data.slots[slot] = id
    return true
  end

  function StateIndex:slot(slot)
    local id = self.data.slots[slot]
    return id and copy(self.data.records[id]) or nil
  end

  function StateIndex:setRecovery(metadata)
    if metadata == nil then
      self.data.recovery = nil
      self.data.records.recovery = nil
      return true
    end
    local detached = copy(metadata)
    if not metadataOk("recovery", detached, "recovery") then
      return nil, "bad_metadata", "Recovery metadata must use the recovery id."
    end
    self.data.records.recovery = detached
    self.data.recovery = "recovery"
    return true
  end

  function StateIndex:recovery()
    return self.data.recovery and copy(self.data.records.recovery) or nil
  end

  function StateIndex:record()
    return copy(self.data)
  end

  return StateIndex
end
