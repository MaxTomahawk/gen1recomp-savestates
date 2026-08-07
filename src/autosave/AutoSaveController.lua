local AutoSaveController = {}
AutoSaveController.__index = AutoSaveController

local TRIGGERS = {
  location_enter = { option = "auto_location" },
  trainer_battle_start = { option = "auto_trainer_battle", runtime = "battle" },
  wild_battle_start = { option = "auto_wild_battle", runtime = "battle" },
  battle_end = { option = "auto_after_battle" },
  before_warp = { option = "auto_before_warp", runtime = "overworld" },
}

local function contextKey(trigger, context)
  return trigger .. ":" .. tostring(context.contextKey or context.mapId or "")
end

local function detachedContext(context)
  context = type(context) == "table" and context or {}
  return {
    mapId = context.mapId,
    contextKey = context.contextKey,
    locationName = context.locationName,
    result = context.result,
    battleKind = context.battleKind,
  }
end

function AutoSaveController.new(args)
  assert(type(args) == "table", "AutoSaveController.new needs arguments")
  assert(type(args.service) == "table", "AutoSaveController needs service")
  assert(type(args.checkpoints) == "table", "AutoSaveController needs checkpoints")
  assert(type(args.option) == "function", "AutoSaveController needs option reader")
  return setmetatable({
    service = args.service,
    checkpoints = args.checkpoints,
    option = args.option,
    pending = {},
    pendingByKey = {},
  }, AutoSaveController)
end

function AutoSaveController:onTrigger(trigger, context)
  local definition = TRIGGERS[trigger]
  if not definition then return false, "unsupported_trigger" end
  if not self.option(definition.option) then return false, "disabled" end
  local copy = detachedContext(context)
  copy.contextKey = copy.contextKey or copy.mapId or trigger
  local key = contextKey(trigger, copy)
  local existing = self.pendingByKey[key]
  local entry = { trigger = trigger, context = copy, key = key }
  if existing then
    self.pending[existing] = entry
  else
    self.pending[#self.pending + 1] = entry
    self.pendingByKey[key] = #self.pending
  end
  return true
end

function AutoSaveController:pendingCount()
  return #self.pending
end

-- Some semantic events are themselves the last safe instant for a capture.
-- They must never enter the deferred queue: after player.warped returns, the
-- engine starts mutating the transition and a later snapshot would describe
-- the destination while carrying source-warp metadata.
function AutoSaveController:onImmediateTrigger(trigger, game, context)
  local definition = TRIGGERS[trigger]
  if not definition then return false, "unsupported_trigger" end
  if not self.option(definition.option) then return false, "disabled" end
  if type(game) ~= "table" then
    return false, "runtime_unavailable",
      "The live game was unavailable at the requested capture boundary."
  end

  local ok, capability = pcall(self.checkpoints.inspect, self.checkpoints, game)
  if not ok then return false, "unexpected_error", tostring(capability) end
  if definition.runtime and type(capability) == "table"
      and capability.kind ~= definition.runtime then
    return false, "runtime_mismatch",
      "The event does not match the active checkpoint runtime."
  end
  if type(capability) ~= "table" or not capability.canCapture then
    return false,
      type(capability) == "table" and capability.reason or "runtime_unsafe",
      type(capability) == "table" and capability.message
        or "The current runtime cannot be checkpointed safely."
  end

  local called, result, code, message = pcall(
    self.service.autoSave, self.service, game, trigger, detachedContext(context))
  if not called then return nil, "unexpected_error", tostring(result) end
  return result, code, message
end

local function reindex(self)
  self.pendingByKey = {}
  for index, entry in ipairs(self.pending) do self.pendingByKey[entry.key] = index end
end

function AutoSaveController:tick(game)
  if #self.pending == 0 then return false, "empty" end
  local entry = self.pending[1]
  local ok, capability = pcall(self.checkpoints.inspect, self.checkpoints, game)
  if not ok then return false, "unexpected_error", tostring(capability) end
  local definition = TRIGGERS[entry.trigger]
  if definition and definition.runtime
      and type(capability) == "table" and capability.kind ~= definition.runtime then
    table.remove(self.pending, 1)
    reindex(self)
    return false, "stale_trigger",
      "The deferred event no longer matches the active runtime."
  end
  if type(capability) ~= "table" or not capability.canCapture then
    return false,
      type(capability) == "table" and capability.reason or "runtime_unsafe",
      type(capability) == "table" and capability.message
        or "The current runtime cannot be checkpointed safely."
  end

  entry = table.remove(self.pending, 1)
  reindex(self)
  local called, result, code, message = pcall(
    self.service.autoSave, self.service, game, entry.trigger, entry.context)
  if not called then return nil, "unexpected_error", tostring(result) end
  return result, code, message
end

function AutoSaveController:install(mod)
  mod.events:on("map.entered", function(event)
    event = type(event) == "table" and event or {}
    self:onTrigger("location_enter", {
      mapId = event.mapId,
      contextKey = event.mapId,
    })
  end)
  mod.events:on("battle.ended", function(event)
    event = type(event) == "table" and event or {}
    self:onTrigger("battle_end", {
      contextKey = "battle_end",
      result = event.result,
    })
  end)
  mod.events:on("battle.started", function(event)
    event = type(event) == "table" and event or {}
    local kind = event.kind
    if kind == "trainer" or kind == "wild" then
      self:onTrigger(kind .. "_battle_start", {
        contextKey = kind .. "_battle_start",
        battleKind = kind,
      })
    end
  end)
  mod.events:on("player.warped", function(event)
    event = type(event) == "table" and event or {}
    local fromMap, toMap = event.fromMap, event.toMap
    return self:onImmediateTrigger("before_warp", self.game, {
      mapId = fromMap,
      contextKey = tostring(fromMap or "") .. ">" .. tostring(toMap or ""),
    })
  end)
  mod.hooks:wrap("input.step", function(next, game, dt)
    -- Every gameplay event is emitted later in this same fixed step, so this
    -- is the public, current game handle available to synchronous listeners.
    self.game = game
    self:tick(game)
    return next(game, dt)
  end)
  return self
end

return AutoSaveController
