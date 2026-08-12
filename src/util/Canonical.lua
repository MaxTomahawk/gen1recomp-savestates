return function(DataOnly)
  local Canonical = {}

  local function encodeString(value)
    return ("s%d:%s"):format(#value, value)
  end

  local function encodeNumber(value)
    if value == 0 then return "d0" end
    return "d" .. ("%.17g"):format(value)
  end

  local encodeValue

  local function keyLess(a, b)
    local aType, bType = type(a), type(b)
    if aType ~= bType then return aType < bType end
    return a < b
  end

  encodeValue = function(value)
    local kind = type(value)
    if kind == "nil" then return "n" end
    if kind == "boolean" then return value and "b1" or "b0" end
    if kind == "number" then return encodeNumber(value) end
    if kind == "string" then return encodeString(value) end

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, keyLess)
    local parts = { "t{" }
    for _, key in ipairs(keys) do
      parts[#parts + 1] = type(key) == "number"
        and ("kn%d:"):format(key) or ("ks" .. encodeString(key))
      parts[#parts + 1] = encodeValue(value[key])
      parts[#parts + 1] = ";"
    end
    parts[#parts + 1] = "}"
    return table.concat(parts)
  end

  function Canonical.encode(value)
    local detached, code, message = DataOnly.copy(value)
    if detached == nil and code then return nil, code, message end
    return encodeValue(detached)
  end

  return Canonical
end
