local Time = {}

function Time.relative(createdAt, now)
  if type(createdAt) ~= "number" or type(now) ~= "number" then return "----" end
  local seconds = math.max(0, math.floor(now - createdAt))
  if seconds < 60 then return "NOW" end
  if seconds < 3600 then return ("%dm"):format(math.floor(seconds / 60)) end
  if seconds < 86400 then return ("%dh"):format(math.floor(seconds / 3600)) end
  return ("%dd"):format(math.floor(seconds / 86400))
end

function Time.playTime(seconds)
  if type(seconds) ~= "number" or seconds ~= seconds
      or seconds == math.huge or seconds == -math.huge or seconds < 0 then
    return "----"
  end
  local minutes = math.floor(seconds / 60)
  return ("%02d:%02d"):format(math.floor(minutes / 60), minutes % 60)
end

local function formatDate(seconds, format)
  if type(seconds) ~= "number" or seconds ~= seconds
      or seconds == math.huge or seconds == -math.huge or seconds < 0 then
    return "----"
  end
  local ok, value = pcall(os.date, format, math.floor(seconds))
  return ok and type(value) == "string" and value or "----"
end

function Time.absolute(seconds)
  return formatDate(seconds, "%Y-%m-%d %H:%M")
end

function Time.historyDate(seconds)
  return formatDate(seconds, "%m-%d %H:%M")
end

return Time
