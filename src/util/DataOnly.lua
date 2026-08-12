local DataOnly = {}

local MAX_DEPTH = 128

local function failure(path, detail)
  return nil, "not_data_only", ("Non-data value at %s: %s"):format(path, detail)
end

local function copyValue(value, path, active, depth)
  local kind = type(value)
  if kind == "nil" or kind == "string" or kind == "boolean" then
    return value
  end
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return failure(path, "number must be finite")
    end
    return value
  end
  if kind ~= "table" then return failure(path, kind .. " is unsupported") end
  if getmetatable(value) ~= nil then return failure(path, "metatables are unsupported") end
  if active[value] then return failure(path, "cycles are unsupported") end
  if depth >= MAX_DEPTH then return failure(path, "maximum nesting exceeded") end

  active[value] = true
  local out = {}
  for key, item in pairs(value) do
    local keyKind = type(key)
    if keyKind ~= "string"
        and not (keyKind == "number" and key >= 1 and key % 1 == 0) then
      active[value] = nil
      return failure(path, "keys must be strings or positive integers")
    end
    local child, code, message = copyValue(item,
      path .. "[" .. tostring(key) .. "]", active, depth + 1)
    if code then
      active[value] = nil
      return nil, code, message
    end
    out[key] = child
  end
  active[value] = nil
  return out
end

function DataOnly.copy(value)
  return copyValue(value, "$", {}, 0)
end

return DataOnly
