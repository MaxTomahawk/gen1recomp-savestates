return function(Canonical)
  local Fingerprint = {}
  local bit = require("bit")
  local UINT32 = 4294967296

  local function unsigned(value)
    return value < 0 and value + UINT32 or value
  end

  -- Exact FNV-1a multiplication using 16-bit limbs. This avoids the rounding
  -- a direct 32-bit-by-24-bit product can incur in Lua's double number type.
  local function fnvMultiply(value)
    local low = value % 65536
    local high = math.floor(value / 65536)
    local lowProduct = low * 403 -- low limb of 0x01000193
    local outLow = lowProduct % 65536
    local carry = math.floor(lowProduct / 65536)
    local outHigh = (carry + low * 256 + high * 403) % 65536
    return outHigh * 65536 + outLow
  end

  local function hashes(text)
    local fnv, djb = 2166136261, 5381
    for index = 1, #text do
      local byte = text:byte(index)
      fnv = fnvMultiply(unsigned(bit.bxor(fnv, byte)))
      djb = (djb * 33 + byte) % UINT32
    end
    return fnv, djb
  end

  function Fingerprint.of(checkpoint)
    if type(checkpoint) ~= "table" or type(checkpoint.save) ~= "table" then
      return nil, "missing_persistent_state",
        "Checkpoint has no persistent progress to fingerprint."
    end
    local encoded, code, message = Canonical.encode(checkpoint.save)
    if not encoded then return nil, code, message end
    local first, second = hashes(encoded)
    return ("%08x%08x"):format(first, second)
  end

  return Fingerprint
end
