local Test = dofile("tests/testlib.lua")
local T = Test.new("checkpoint preview metadata")
local DataOnly = dofile("src/util/DataOnly.lua")
local Preview = dofile("src/state/Preview.lua")(DataOnly)

local function speciesName(id)
  return ({ PIKACHU = "PIKACHU", NIDORINO = "NIDORINO", GEODUDE = "GEODUDE" })[id]
end

local captured, captureCode, captureMessage = Preview.capture({
  playTime = 16620,
  inventory = { BOULDERBADGE = 1, THUNDERBADGE = true, POTION = 4 },
  party = {
    { species = "PIKACHU", nickname = "SPARKY", level = 22, hp = 45,
      stats = { hp = 57 }, status = "PAR" },
    { species = "NIDORINO", level = 19, hp = 38, stats = { hp = 52 } },
    { species = "GEODUDE", level = 16, hp = 0, stats = { hp = 49 }, status = "FRZ" },
    { species = "PIKACHU", level = 20, hp = 51, stats = { hp = 61 } },
    { species = "NIDORINO", level = 18, hp = 34, stats = { hp = 46 } },
    { species = "GEODUDE", level = 21, hp = 48, stats = { hp = 58 } },
  },
}, {
  speciesName = speciesName,
  badgeIds = { "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE" },
})

T:check(captured ~= nil, "valid canonical save creates preview: "
  .. tostring(captureCode or captureMessage))
T:eq(captured.playTime, 16620, "preview keeps captured play time seconds")
T:eq(captured.badgeCount, 2, "preview counts captured badge inventory")
T:eq(captured.badgeTotal, 4, "preview keeps captured badge total")
T:eq(#captured.party, 6, "preview keeps complete six-mon party")
T:eq(captured.party[1].name, "SPARKY", "nickname takes precedence over species")
T:eq(captured.party[2].name, "NIDORINO", "species name is fallback without nickname")
T:eq(captured.party[1].level, 22, "preview keeps captured level")
T:eq(captured.party[1].hp, 45, "preview keeps captured current HP")
T:eq(captured.party[1].maxHp, 57, "preview keeps captured maximum HP")
T:eq(captured.party[3].hp, 0, "preview keeps fainted zero HP")
T:eq(captured.party[3].maxHp, 49, "fainted preview retains captured maximum HP")
T:eq(captured.party[1].status, nil, "preview never stores status condition")
T:eq(captured.party[3].status, nil, "preview excludes every party status condition")

local empty = assert(Preview.capture({ playTime = 0, inventory = {}, party = {} }, {
  speciesName = speciesName,
  badgeIds = { "BOULDERBADGE" },
}))
T:eq(#empty.party, 0, "preview supports zero party members")

local malformed, malformedCode = Preview.validate({
  playTime = 10,
  badgeCount = 1,
  badgeTotal = 1,
  party = {
    { name = "PIKACHU", level = 5, hp = 4, maxHp = 10, status = "PSN" },
  },
})
T:eq(malformed, nil, "preview rejects stored status fields")
T:eq(malformedCode, "corrupt_preview", "malformed preview has stable error code")

local impossible, impossibleCode = Preview.validate({
  playTime = 10,
  badgeCount = 2,
  badgeTotal = 1,
  party = {},
})
T:eq(impossible, nil, "preview rejects impossible badge progress")
T:eq(impossibleCode, "corrupt_preview", "impossible badge progress has stable code")

T:finish()
