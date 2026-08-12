return function(DataOnly)
  local Preview = {}

  local function finite(value)
    return type(value) == "number" and value == value
      and value ~= math.huge and value ~= -math.huge
  end

  local function integer(value, minimum)
    return finite(value) and value % 1 == 0 and value >= minimum
  end

  local function denseList(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
      if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
      count = count + 1
    end
    return count == #value
  end

  local function onlyKeys(value, allowed)
    for key in pairs(value) do
      if not allowed[key] then return false end
    end
    return true
  end

  local function failure()
    return nil, "corrupt_preview", "Snapshot preview metadata is corrupt."
  end

  function Preview.validate(value)
    local copy, code, message = DataOnly.copy(value)
    if not copy then return nil, code, message end
    if type(copy) ~= "table" or not onlyKeys(copy, {
      playTime = true, badgeCount = true, badgeTotal = true, party = true,
    }) or not finite(copy.playTime) or copy.playTime < 0
        or not integer(copy.badgeCount, 0) or not integer(copy.badgeTotal, 0)
        or copy.badgeCount > copy.badgeTotal or not denseList(copy.party)
        or #copy.party > 6 then
      return failure()
    end
    for _, mon in ipairs(copy.party) do
      if type(mon) ~= "table" or not onlyKeys(mon, {
        species = true, name = true, level = true, hp = true, maxHp = true,
      }) or type(mon.name) ~= "string" or mon.name == ""
          or (mon.species ~= nil and
            (type(mon.species) ~= "string" or mon.species == ""))
          or not integer(mon.level, 1) or not integer(mon.hp, 0)
          or not integer(mon.maxHp, 1) or mon.hp > mon.maxHp then
        return failure()
      end
    end
    return copy
  end

  local function partyName(mon, speciesName)
    if type(mon.nickname) == "string" and mon.nickname ~= "" then
      return mon.nickname
    end
    if type(speciesName) == "function" then
      local ok, name = pcall(speciesName, mon.species)
      if ok and type(name) == "string" and name ~= "" then return name end
    end
    return mon.species
  end

  function Preview.capture(save, context)
    if type(save) ~= "table" then
      return nil, "preview_unavailable", "Checkpoint save data is unavailable."
    end
    context = type(context) == "table" and context or {}
    local badgeIds = context.badgeIds
    if not denseList(badgeIds or {}) then
      return nil, "preview_unavailable", "Badge metadata is unavailable."
    end
    local inventory = type(save.inventory) == "table" and save.inventory or {}
    local badgeCount = 0
    for _, id in ipairs(badgeIds or {}) do
      if type(id) ~= "string" or id == "" then
        return nil, "preview_unavailable", "Badge metadata is invalid."
      end
      if inventory[id] then badgeCount = badgeCount + 1 end
    end
    local party = {}
    local sourceParty = type(save.party) == "table" and save.party or {}
    for index = 1, math.min(#sourceParty, 6) do
      local mon = sourceParty[index]
      local stats = type(mon) == "table" and mon.stats or nil
      if type(mon) ~= "table" or type(mon.species) ~= "string"
          or not integer(mon.level, 1) or not integer(mon.hp, 0)
          or type(stats) ~= "table" or not integer(stats.hp, 1)
          or mon.hp > stats.hp then
        return nil, "preview_unavailable", "Checkpoint party data is invalid."
      end
      party[#party + 1] = {
        species = mon.species,
        name = partyName(mon, context.speciesName),
        level = mon.level,
        hp = mon.hp,
        maxHp = stats.hp,
      }
    end
    return Preview.validate({
      playTime = finite(save.playTime) and save.playTime >= 0 and save.playTime or 0,
      badgeCount = badgeCount,
      badgeTotal = #(badgeIds or {}),
      party = party,
    })
  end

  return Preview
end
