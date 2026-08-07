local Time = {}

function Time.relative(createdAt, now)
  if type(createdAt) ~= "number" or type(now) ~= "number" then return "----" end
  local seconds = math.max(0, math.floor(now - createdAt))
  if seconds < 60 then return "NOW" end
  if seconds < 3600 then return ("%dm"):format(math.floor(seconds / 60)) end
  if seconds < 86400 then return ("%dh"):format(math.floor(seconds / 3600)) end
  return ("%dd"):format(math.floor(seconds / 86400))
end

return Time
