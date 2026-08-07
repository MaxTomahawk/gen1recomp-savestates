local Test = dofile("tests/testlib.lua")
local T = Test.new("autosave deduplication")
local DataOnly = dofile("src/util/DataOnly.lua")
local Canonical = dofile("src/util/Canonical.lua")(DataOnly)
local Fingerprint = dofile("src/util/Fingerprint.lua")(Canonical)
local Deduplicator = dofile("src/autosave/Deduplicator.lua")

local left = {
  save = {
    money = 3000,
    flags = { GOT_STARTER = true, BEAT_BROCK = false },
    party = { { species = "BULBASAUR", hp = 19 } },
  },
}
local right = {
  save = {
    party = { { hp = 19, species = "BULBASAUR" } },
    flags = { BEAT_BROCK = false, GOT_STARTER = true },
    money = 3000,
  },
}

local leftCanonical = Canonical.encode(left.save)
local rightCanonical = Canonical.encode(right.save)
T:eq(leftCanonical, rightCanonical, "table insertion order does not affect canonical data")

local first, firstCode, firstMessage = Fingerprint.of(left)
local reordered = Fingerprint.of(right)
T:check(type(first) == "string" and first:match("^[0-9a-f]+$") and #first == 16,
  "fingerprint is a compact lowercase 64-bit hex value: " .. tostring(firstCode or firstMessage))
T:eq(reordered, first, "table insertion order does not affect fingerprint")

local moneyChanged = Fingerprint.of({ save = {
  money = 2999, flags = left.save.flags, party = left.save.party,
} })
T:check(moneyChanged ~= first, "money changes the persistent fingerprint")

local flagsChanged = Fingerprint.of({ save = {
  money = 3000, flags = { GOT_STARTER = false, BEAT_BROCK = false },
  party = left.save.party,
} })
T:check(flagsChanged ~= first, "event flags change the persistent fingerprint")

local partyChanged = Fingerprint.of({ save = {
  money = 3000, flags = left.save.flags,
  party = { { species = "BULBASAUR", hp = 18 } },
} })
T:check(partyChanged ~= first, "party state changes the persistent fingerprint")

local invalid, invalidCode = Fingerprint.of({})
T:eq(invalid, nil, "checkpoint without progress has no fingerprint")
T:eq(invalidCode, "missing_persistent_state", "missing progress has a stable code")

local dedupe = Deduplicator.new(5)
local newest = {
  trigger = "location_enter", locationId = "PALLET_TOWN",
  contextKey = "PALLET_TOWN", createdAt = 100, fingerprint = first,
}

local withinCooldown = {
  trigger = "location_enter", locationId = "PALLET_TOWN",
  contextKey = "PALLET_TOWN", createdAt = 103, fingerprint = moneyChanged,
}
T:eq(dedupe:decide(withinCooldown, newest, 103), "skip",
  "same trigger and context within five seconds is skipped")

local atBoundary = {
  trigger = "location_enter", locationId = "PALLET_TOWN",
  contextKey = "PALLET_TOWN", createdAt = 105, fingerprint = first,
}
T:eq(dedupe:decide(atBoundary, newest, 105), "replace",
  "same semantic state at the cooldown boundary replaces newest")

local changedAfterCooldown = {
  trigger = "location_enter", locationId = "PALLET_TOWN",
  contextKey = "PALLET_TOWN", createdAt = 106, fingerprint = moneyChanged,
}
T:eq(dedupe:decide(changedAfterCooldown, newest, 106), "append",
  "changed persistent state after cooldown appends")

local anotherTrigger = {
  trigger = "trainer_battle_start", locationId = "PALLET_TOWN",
  contextKey = "TRAINER:1", createdAt = 101, fingerprint = first,
}
T:eq(dedupe:decide(anotherTrigger, newest, 101), "append",
  "a different trigger appends even inside the cooldown")

local anotherContext = {
  trigger = "location_enter", locationId = "PALLET_TOWN",
  contextKey = "PALLET_TOWN:DOOR", createdAt = 101, fingerprint = first,
}
T:eq(dedupe:decide(anotherContext, newest, 101), "replace",
  "outside cooldown context, same trigger/map/fingerprint replaces newest")

T:eq(dedupe:decide(newest, nil, 100), "append",
  "an empty history always appends")

T:finish()
