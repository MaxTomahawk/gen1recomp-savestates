local AutoSaveController = {}
AutoSaveController.__index = AutoSaveController

local TRIGGERS = {
  location_enter = { option = "auto_location" },
  battle_end = { option = "auto_after_battle" },
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

local function reindex(self)
  self.pendingByKey = {}
  for index, entry in ipairs(self.pending) do self.pendingByKey[entry.key] = index end
end

function AutoSaveController:tick(game)
  if #self.pending == 0 then return false, "empty" end
  local ok, capability = pcall(self.checkpoints.inspect, self.checkpoints, game)
  if not ok then return false, "unexpected_error", tostring(capability) end
  if type(capability) ~= "table" or not capability.canCapture then
    return false,
      type(capability) == "table" and capability.reason or "runtime_unsafe",
      type(capability) == "table" and capability.message
        or "The current runtime cannot be checkpointed safely."
  end

  local entry = table.remove(self.pending, 1)
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
  mod.hooks:wrap("input.step", function(next, game, dt)
    self:tick(game)
    return next(game, dt)
  end)
  return self
end

return AutoSaveController
