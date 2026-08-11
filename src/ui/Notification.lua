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
  corrupt_metadata = true,
  invalid_checkpoint = true,
  invalid_content = true,
  invalid_map = true,
  invalid_position = true,
  migration_failed = true,
  missing_checkpoint = true,
  missing_migration = true,
  missing_persistent_state = true,
  not_data_only = true,
  payload_missing = true,
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
    return "QUICK SAVED", detail.locationName
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

-- A public Modern UI adapter reads this descriptive model only. The active
-- notification remains source-owned, including replacement and expiration;
-- no checkpoint/runtime data crosses the presentation seam.
function Notification:modernModel()
  local active = self:current()
  if not active then return nil end
  local severity = (SAVE_SUCCESSES[active.kind] or LOAD_SUCCESSES[active.kind])
      and "success"
    or (active.kind == "save_failed" or active.kind == "load_failed")
      and "error" or "warning"
  return {
    id = "savestates:notification",
    title = active.title,
    detail = active.detail,
    severity = severity,
  }
end

local function dropLastCharacter(text)
  local first = #text
  while first > 1 do
    local byte = text:byte(first)
    if not byte or byte < 0x80 or byte > 0xBF then break end
    first = first - 1
  end
  return text:sub(1, first - 1)
end

local function fitLine(Font, value, maximum)
  local text = tostring(value or "")
  if Font.width(text) <= maximum then return text end
  local suffix = "."
  while text ~= "" and Font.width(text .. suffix) > maximum do
    text = dropLastCharacter(text)
  end
  return text .. suffix
end

local function titleLines(Font, value, maximum)
  local title = tostring(value or "")
  if Font.width(title) <= maximum then return { title } end
  local wrapped
  local search = 1
  while true do
    local split = title:find(" ", search, true)
    if not split then break end
    local first, second = title:sub(1, split - 1), title:sub(split + 1)
    if first ~= "" and second ~= ""
        and Font.width(first) <= maximum and Font.width(second) <= maximum then
      wrapped = { first, second }
    end
    search = split + 1
  end
  return wrapped or { fitLine(Font, title, maximum) }
end

function Notification:drawNativeHud(Font, viewport)
  local active = self:current()
  if not active or not love or not love.graphics or not Font
      or type(viewport) ~= "table" then return false end
  local width = tonumber(viewport.width)
  local scale = tonumber(viewport.scale)
  local dpiX = tonumber(viewport.dpiX) or 1
  local dpiY = tonumber(viewport.dpiY) or 1
  if not width or not scale or scale <= 0 or dpiX <= 0 or dpiY <= 0 then
    return false
  end
  local maximum = 18 * 8
  local titles = titleLines(Font, active.title, maximum)
  local detail = active.detail and fitLine(Font, active.detail, maximum) or nil
  local tiles = 20
  local height = #titles > 1 and 7 or 5
  local tx, ty = 0, 0
  local function centered(line)
    return math.max(0, math.floor((160 - Font.width(line)) / 2))
  end

  -- render.hud is already the engine-owned post-composite screen-space pass.
  -- Reuse its exact logical scale and DPI conversion, centre the native
  -- 160-pixel banner in the physical viewport, and leave one logical tile of
  -- breathing room above it. Touch controls draw after this public hook.
  local sx, sy = scale / dpiX, scale / dpiY
  local x = math.max(0, math.floor((width - 160 * sx) / 2))
  local y = math.max(0, math.floor(8 * sy))
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.translate(x, y)
  love.graphics.scale(sx, sy)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(tx, ty, tiles, height)
  love.graphics.setColor(0, 0, 0, 1)
  for index, line in ipairs(titles) do
    Font.draw(line, centered(line), (ty + index) * 8)
  end
  if detail then
    Font.draw(detail, centered(detail), (ty + (#titles > 1 and 4 or 3)) * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.pop()
  return true
end

return Notification
