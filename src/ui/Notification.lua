local Notification = {}
Notification.__index = Notification

local SAVE_SUCCESSES = {
  auto_saved = true,
  quick_saved = true,
  slot_saved = true,
  state_deleted = true,
}
local LOAD_SUCCESSES = { state_loaded = true, load_undone = true }
local INCOMPATIBLE = {
  bad_format = true,
  corrupt_identity = true,
  unsupported_format = true,
  unsupported_runtime_kind = true,
  wrong_game = true,
  wrong_playthrough = true,
}
local REASONS = {
  animation_busy = "ANIMATION IS BUSY",
  movement_busy = "MOVEMENT IS BUSY",
  screen_busy = "CLOSE THE ACTIVE MENU",
  script_busy = "SCRIPT IS BUSY",
  transition_busy = "TRANSITION IS BUSY",
}

local function hasWarning(detail, expected)
  for _, warning in ipairs(type(detail.warnings) == "table" and detail.warnings or {}) do
    if warning == expected then return true end
  end
  return false
end

local function text(kind, detail)
  detail = detail or {}
  if kind == "quick_saved" then
    return ("QUICK SAVED · %s/%s"):format(
      tostring(detail.count or "-"), tostring(detail.limit or "-")),
      detail.locationName
  elseif kind == "auto_saved" then
    return "AUTO SAVED", detail.locationName
  elseif kind == "slot_saved" then
    return "SLOT SAVED", detail.label or detail.locationName
  elseif kind == "state_loaded" then
    return "STATE LOADED", hasWarning(detail, "engine_version_mismatch")
      and "ENGINE VERSION WARN" or detail.locationName
  elseif kind == "load_undone" then
    return "LOAD UNDONE", hasWarning(detail, "engine_version_mismatch")
      and "ENGINE VERSION WARN" or detail.locationName
  elseif kind == "state_deleted" then
    return "STATE DELETED"
  elseif kind == "save_rejected" then
    return "CAN'T SAVE STATE NOW", REASONS[detail.code] or detail.message
  elseif kind == "save_failed" then
    return "SAVE STATE FAILED", detail.message
  elseif kind == "load_failed" then
    if detail.code == "no_quick_save" then return "NO QUICK SAVE" end
    if INCOMPATIBLE[detail.code] then return "STATE INCOMPATIBLE" end
    return "LOAD FAILED", detail.message
  end
  return "SAVE STATES", detail.message
end

function Notification.new(args)
  assert(type(args) == "table" and type(args.clock) == "function",
    "Notification.new needs a clock")
  return setmetatable({
    clock = args.clock,
    duration = args.duration or 1.5,
    isEnabled = args.isEnabled,
    active = nil,
  }, Notification)
end

function Notification:show(kind, detail)
  local group = SAVE_SUCCESSES[kind] and "save"
    or (LOAD_SUCCESSES[kind] and "load" or nil)
  if group and type(self.isEnabled) == "function" and not self.isEnabled(group) then
    return false
  end
  local title, secondary = text(kind, detail)
  self.active = {
    kind = kind,
    title = tostring(title),
    detail = secondary and tostring(secondary) or nil,
    shownAt = self.clock(),
  }
  return true
end

function Notification:current()
  local active = self.active
  if not active then return nil end
  if self.clock() - active.shownAt >= self.duration then
    self.active = nil
    return nil
  end
  return active
end

function Notification:draw(viewport, Font)
  local active = self:current()
  if not active or not love or not love.graphics or not Font then return false end
  viewport = viewport or {}
  local scale = viewport.scale or ((viewport.gameHeight or 144) / 144)
  if type(scale) ~= "number" or scale <= 0 then scale = 1 end
  local widest = math.max(Font.width(active.title),
    active.detail and Font.width(active.detail) or 0)
  local tiles = math.max(12, math.min(20, math.ceil(widest / 8) + 2))
  local tx, ty = 20 - tiles, 13

  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.translate(viewport.gameX or 0, viewport.gameY or 0)
  love.graphics.scale(scale, scale)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(tx, ty, tiles, 5)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(active.title, (tx + 1) * 8, (ty + 1) * 8)
  if active.detail then
    Font.draw(active.detail, (tx + 1) * 8, (ty + 3) * 8)
  end
  love.graphics.pop()
  return true
end

return Notification
