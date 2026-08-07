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
T:eq(current.title, "QUICK SAVED · 5/5", "quicksave title includes rolling count")
T:eq(current.detail, "CERULEAN GYM", "quicksave detail includes location")

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

T:finish()
