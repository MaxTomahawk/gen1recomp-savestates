local Test = dofile("tests/testlib.lua")
local T = Test.new("notification overlay")
local Notification = dofile("src/ui/Notification.lua")

local now = 10
local enabled = { save = true, load = true }
local notice = Notification.new({
  clock = function() return now end,
  duration = 1.5,
  isEnabled = function(group) return enabled[group] end,
})

T:eq(notice:current(), nil, "notification starts hidden")
T:eq(notice:show("quick_saved", {
  count = 5, limit = 5, locationName = "CERULEAN GYM",
}), true, "quicksave notification is accepted")
local current = notice:current()
T:eq(current.title, "QUICK SAVED", "quicksave title omits unhelpful rolling count")
T:eq(current.detail, "CERULEAN GYM", "quicksave detail includes location")
local modern = notice:modernModel()
T:eq(modern.id, "savestates:notification",
  "modern presentation uses a stable source-owned replacement key")
T:eq(modern.title, "QUICK SAVED",
  "modern presentation retains the captured notification title")
T:eq(modern.detail, "CERULEAN GYM",
  "modern presentation retains the captured notification detail")
T:eq(modern.severity, "success",
  "successful saves expose a presentation-only success severity")
T:eq(modern.status, nil,
  "modern presentation deliberately excludes gameplay status metadata")

now = 10.5
notice:show("state_loaded", { locationName = "PALLET TOWN" })
current = notice:current()
T:eq(current.title, "STATE LOADED", "new notification replaces visible one")
T:eq(current.detail, "PALLET TOWN", "replacement carries new detail")
notice:show("state_loaded", {
  locationName = "PALLET TOWN", warnings = { "engine_version_mismatch" },
})
current = notice:current()
T:eq(current.title, "STATE LOADED", "warning-grade load still succeeds")
T:eq(current.detail, "ENGINE VERSION WARN",
  "engine mismatch is visible instead of silently swallowed")
now = 11.9
T:check(notice:current() ~= nil, "replacement owns a fresh lifetime")
now = 12.01
T:eq(notice:current(), nil, "notification expires without input")

enabled.save = false
T:eq(notice:show("slot_saved", { slot = 3 }), false,
  "disabled save success notification stays hidden")
T:eq(notice:current(), nil, "disabled save success creates no overlay")
enabled.load = false
T:eq(notice:show("load_undone", {}), false,
  "disabled load success notification stays hidden")

T:eq(notice:show("save_rejected", {
  code = "script_busy", message = "Wait for the active script to finish.",
}), true, "safety refusal remains visible despite success toggle")
current = notice:current()
T:eq(current.title, "CAN'T SAVE STATE NOW", "unsafe capture has required title")
T:eq(current.detail, "SCRIPT IS BUSY", "unsafe capture gives concise reason")

now = 13
notice:show("load_failed", { code = "no_quick_save" })
T:eq(notice:current().title, "NO QUICK SAVE", "empty quickload has product message")
notice:show("load_failed", { code = "wrong_playthrough" })
T:eq(notice:current().title, "STATE INCOMPATIBLE",
  "identity mismatch has compatibility message")
notice:show("load_failed", { code = "invalid_map" })
T:eq(notice:current().title, "STATE INCOMPATIBLE",
  "unavailable checkpoint content has compatibility message")
notice:show("save_failed", { message = "disk unavailable" })
T:eq(notice:current().title, "SAVE STATE FAILED", "save failure has required title")
notice:show("state_deleted", {})
T:eq(notice:current().title, "SAVE STATE FAILED",
  "disabled deletion success does not replace visible failure")

enabled.save = true
notice:show("auto_saved", { locationName = "ROUTE 24" })
T:eq(notice:current().title, "AUTO SAVED", "autosave has required title")
notice:show("state_deleted", {})
T:eq(notice:current().title, "STATE DELETED", "deletion has required title")

local drawn = {}
local boxes = {}
local transforms = {}
love = { graphics = {
  push = function() end,
  origin = function() transforms[#transforms + 1] = { "origin" } end,
  translate = function(x, y) transforms[#transforms + 1] = { "translate", x, y } end,
  scale = function(x, y) transforms[#transforms + 1] = { "scale", x, y } end,
  setColor = function() end,
  pop = function() end,
} }
local Font = {
  width = function(text) return #text * 8 end,
  drawBox = function(tx, ty, tw, th)
    boxes[#boxes + 1] = { tx = tx, ty = ty, tw = tw, th = th }
  end,
  draw = function(text, x, y) drawn[#drawn + 1] = { text = text, x = x, y = y } end,
}
notice:show("auto_saved", { locationName = "ROUTE 24" })
local portrait = {
  width = 550, height = 960, gameX = 35, gameY = 264,
  gameWidth = 480, gameHeight = 432, scale = 3, dpiX = 1, dpiY = 1,
}
T:eq(notice:drawNativeHud(Font, portrait), true,
  "short notification draws in the public screen-space HUD pass")
local shortBox = boxes[#boxes]
T:check(shortBox and shortBox.tx == 0 and shortBox.ty == 0 and shortBox.tw == 20,
  "short notification uses the native full-width logical box")
T:eq(drawn[1].x, 80 - Font.width(drawn[1].text) / 2,
  "notification title is horizontally centered")
T:eq(drawn[2].x, 80 - Font.width(drawn[2].text) / 2,
  "notification detail is horizontally centered")
T:eq(transforms[2] and transforms[2][1], "translate",
  "portrait banner applies a screen-space translation")
T:eq(transforms[2] and transforms[2][2], 35,
  "portrait banner is centred horizontally")
T:eq(transforms[2] and transforms[2][3], 24,
  "portrait banner stays one logical tile from the physical top")
T:eq(transforms[3] and transforms[3][1], "scale",
  "portrait banner applies the engine scale")
T:eq(transforms[3] and transforms[3][2], 3,
  "native HUD uses the engine-provided horizontal scale")
T:eq(transforms[3] and transforms[3][3], 3,
  "native HUD uses the engine-provided vertical scale")
drawn, boxes = {}, {}
notice:show("save_failed", { message = string.rep("X", 40) })
T:eq(notice:drawNativeHud(Font, portrait), true,
  "long failure notification stays in the screen-space HUD pass")
T:eq(drawn[1].text, "SAVE STATE FAILED", "fitting preserves a short title")
T:eq(drawn[2].text, string.rep("X", 17) .. ".",
  "long detail is visibly truncated to the maximum box interior")
local box = boxes[#boxes]
T:check(box and box.tx == 0 and box.ty == 0 and box.tw == 20 and box.th == 5,
  "notification uses a full-width banner at its translated physical-top origin")

drawn = {}
notice:show("save_rejected", {
  code = "script_busy", message = "Wait for the active script to finish.",
})
T:eq(notice:drawNativeHud(Font, portrait), true,
  "long required refusal title draws through the screen-space HUD pass")
T:eq(drawn[1].text, "CAN'T SAVE STATE", "long title wraps at a word boundary")
T:eq(drawn[2].text, "NOW", "wrapped title retains its complete required wording")
T:eq(drawn[3].text, "SCRIPT IS BUSY", "wrapped title leaves room for concise reason")
box = boxes[#boxes]
T:check(box and box.tx == 0 and box.ty == 0 and box.tw == 20 and box.th == 7,
  "wrapped banner grows down from the physical top instead of entering touch controls")

T:finish()
