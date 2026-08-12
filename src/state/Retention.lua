local Retention = {}

function Retention.selectRemovals(entries, maxCount)
  if type(entries) ~= "table" or type(maxCount) ~= "number"
      or maxCount < 0 or maxCount % 1 ~= 0 then
    return nil, "invalid_limit", "Retention limit must be a nonnegative integer."
  end
  local rolling = {}
  for _, entry in ipairs(entries) do
    if type(entry) == "table"
        and (entry.stateClass == "quick" or entry.stateClass == "auto")
        and type(entry.id) == "string" then
      rolling[#rolling + 1] = entry.id
    end
  end
  local removals = {}
  for i = #rolling, maxCount + 1, -1 do
    removals[#removals + 1] = rolling[i]
  end
  return removals
end

return Retention
