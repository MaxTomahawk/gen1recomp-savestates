local Deduplicator = {}
Deduplicator.__index = Deduplicator

function Deduplicator.new(cooldownSeconds)
  assert(type(cooldownSeconds) == "number" and cooldownSeconds >= 0,
    "cooldown must be a nonnegative number")
  return setmetatable({ cooldown = cooldownSeconds }, Deduplicator)
end

local function context(metadata)
  if type(metadata) ~= "table" then return nil end
  return metadata.contextKey or metadata.locationId or ""
end

function Deduplicator:decide(candidate, newest, now)
  if type(newest) ~= "table" then return "append" end
  if type(candidate) ~= "table" then return "append" end

  local sameTrigger = candidate.trigger == newest.trigger
  local elapsed = (tonumber(now) or tonumber(candidate.createdAt) or 0)
    - (tonumber(newest.createdAt) or 0)
  if sameTrigger and context(candidate) == context(newest)
      and elapsed < self.cooldown then
    return "skip"
  end

  if sameTrigger and candidate.locationId == newest.locationId
      and type(candidate.fingerprint) == "string"
      and candidate.fingerprint ~= ""
      and candidate.fingerprint == newest.fingerprint then
    return "replace"
  end
  return "append"
end

return Deduplicator
