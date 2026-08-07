local Test = dofile("tests/testlib.lua")
local T = Test.new("autosave controller")
local AutoSaveController = dofile("src/autosave/AutoSaveController.lua")

local calls = {}
local service = {}
function service:autoSave(game, trigger, context)
  calls[#calls + 1] = { game = game, trigger = trigger, context = context }
  return { metadata = { trigger = trigger } }
end
local checkpoints = {
  capability = {
    canCapture = false, kind = "overworld", reason = "transition_busy",
    message = "Wait for transition.",
  },
}
function checkpoints:inspect() return self.capability end
local options = {
  auto_location = true,
  auto_after_battle = false,
  auto_before_warp = false,
  auto_trainer_battle = true,
  auto_wild_battle = true,
}
local controller = AutoSaveController.new({
  service = service,
  checkpoints = checkpoints,
  option = function(key) return options[key] end,
})
local game = {}

local disabled, disabledCode = controller:onTrigger(
  "battle_end", { contextKey = "battle:1" })
T:eq(disabled, false, "disabled autosave trigger is ignored")
T:eq(disabledCode, "disabled", "disabled trigger has stable status")
T:eq(controller:pendingCount(), 0, "disabled trigger is not queued")

local queuedBattle, queuedBattleCode = controller:onTrigger(
  "trainer_battle_start", { contextKey = "trainer:1" })
T:eq(queuedBattle, true, "trainer battle trigger queues for a proven safe point")
T:eq(queuedBattleCode, nil, "supported trainer trigger has no error")
T:eq(controller:pendingCount(), 1, "battle trigger waits while intro is unsafe")
checkpoints.capability = {
  canCapture = false, kind = "battle", reason = "battle_phase_busy",
  message = "Wait for the command menu.",
}
local introWait, introCode = controller:tick(game)
T:eq(introWait, false, "unsafe battle intro defers autosave")
T:eq(introCode, "battle_phase_busy", "battle intro preserves capability reason")
controller.pending, controller.pendingByKey = {}, {}
checkpoints.capability = {
  canCapture = false, kind = "overworld", reason = "transition_busy",
  message = "Wait for transition.",
}

T:eq(controller:onTrigger("location_enter", {
  mapId = "PALLET_TOWN", contextKey = "PALLET_TOWN",
}), true, "enabled location trigger queues")
T:eq(controller:pendingCount(), 1, "location trigger is pending")
local waiting, waitingCode = controller:tick(game)
T:eq(waiting, false, "unsafe runtime defers pending autosave")
T:eq(waitingCode, "transition_busy", "deferred autosave preserves capability reason")
T:eq(controller:pendingCount(), 1, "unsafe pending event remains queued")
T:eq(#calls, 0, "unsafe tick never asks service to capture")

checkpoints.capability = { canCapture = true, canRestore = true, kind = "overworld" }
local saved, saveCode, saveMessage = controller:tick(game)
T:check(saved ~= nil, "settled runtime drains pending autosave: "
  .. tostring(saveCode or saveMessage))
T:eq(calls[1].trigger, "location_enter", "controller forwards semantic trigger")
T:eq(calls[1].context.mapId, "PALLET_TOWN", "controller forwards safe event metadata")
T:eq(controller:pendingCount(), 0, "attempted event leaves pending queue")

controller:onTrigger("location_enter", { mapId = "ROUTE_1", contextKey = "ROUTE_1" })
controller:onTrigger("location_enter", { mapId = "ROUTE_1", contextKey = "ROUTE_1" })
T:eq(controller:pendingCount(), 1, "same pending trigger/context coalesces")
controller:onTrigger("location_enter", { mapId = "VIRIDIAN_CITY", contextKey = "VIRIDIAN_CITY" })
T:eq(controller:pendingCount(), 2, "different pending context remains distinct")
controller:tick(game)
T:eq(controller:pendingCount(), 1, "controller drains at most one autosave per tick")

local eventHandlers, hookHandlers = {}, {}
local mod = {
  events = { on = function(_, name, callback) eventHandlers[name] = callback end },
  hooks = { wrap = function(_, name, callback) hookHandlers[name] = callback end },
}
local installed = AutoSaveController.new({
  service = service,
  checkpoints = checkpoints,
  option = function(key) return options[key] end,
})
installed:install(mod)
T:eq(type(eventHandlers["map.entered"]), "function",
  "installation uses public location event")
T:eq(type(eventHandlers["battle.ended"]), "function",
  "installation uses public battle-end event")
T:eq(type(hookHandlers["input.step"]), "function",
  "installation uses fixed-step safe retry hook")
T:eq(type(eventHandlers["battle.started"]), "function",
  "installation subscribes to semantic battle start")
T:eq(type(eventHandlers["player.warped"]), "function",
  "installation subscribes to the public pre-transition warp event")

local noGameWarp, noGameWarpCode = eventHandlers["player.warped"]({
  fromMap = "PALLET_TOWN", toMap = "REDS_HOUSE_1F",
})
T:eq(noGameWarp, false, "disabled before-warp capture is ignored")
T:eq(noGameWarpCode, "disabled", "disabled before-warp status is explicit")

eventHandlers["map.entered"]({ mapId = "CERULEAN_CITY", via = "warp" })
local downstream = 0
hookHandlers["input.step"](function(target, dt)
  T:check(target == game, "input wrapper forwards live game")
  T:eq(dt, 1 / 60, "input wrapper forwards fixed dt")
  downstream = downstream + 1
end, game, 1 / 60)
T:eq(downstream, 1, "autosave hook always calls downstream input step")
T:eq(calls[#calls].trigger, "location_enter", "installed event reaches service when safe")
T:eq(calls[#calls].context.contextKey, "CERULEAN_CITY",
  "installed location event derives semantic context")

options.auto_before_warp = true
local beforeWarpCalls = #calls
local beforeWarp, beforeWarpCode = eventHandlers["player.warped"]({
  fromMap = "CERULEAN_CITY", toMap = "CERULEAN_GYM",
})
T:check(beforeWarp ~= nil,
  "before-warp event captures synchronously: " .. tostring(beforeWarpCode))
T:eq(#calls, beforeWarpCalls + 1,
  "before-warp event cannot be deferred beyond the transition boundary")
T:eq(calls[#calls].game, game, "before-warp capture uses the live fixed-step game")
T:eq(calls[#calls].trigger, "before_warp", "before-warp trigger is canonical")
T:eq(calls[#calls].context.contextKey, "CERULEAN_CITY>CERULEAN_GYM",
  "before-warp dedupe context contains both sides of the warp")
T:eq(calls[#calls].context.mapId, "CERULEAN_CITY",
  "before-warp state remains labeled with its source map")

checkpoints.capability = {
  canCapture = false, kind = "overworld", reason = "movement_busy",
  message = "Wait for movement.",
}
beforeWarpCalls = #calls
local unsafeWarp, unsafeWarpCode = eventHandlers["player.warped"]({
  fromMap = "CERULEAN_GYM", toMap = "CERULEAN_CITY",
})
T:eq(unsafeWarp, false, "unsafe pre-transition boundary fails closed")
T:eq(unsafeWarpCode, "movement_busy", "warp rejection preserves capability reason")
T:eq(#calls, beforeWarpCalls, "unsafe warp never invokes the save service")
T:eq(installed:pendingCount(), 0,
  "unsafe before-warp event is never deferred into the destination map")
checkpoints.capability = { canCapture = true, canRestore = true, kind = "overworld" }

options.auto_after_battle = true
eventHandlers["battle.ended"]({ result = "win" })
T:eq(installed:pendingCount(), 1, "enabled battle end queues for overworld return")

eventHandlers["battle.started"]({ kind = "trainer" })
T:eq(installed:pendingCount(), 2,
  "trainer battle start queues independently for the safe decision menu")
eventHandlers["battle.started"]({ kind = "wild" })
T:eq(installed:pendingCount(), 3,
  "wild battle start queues independently for the safe decision menu")
eventHandlers["battle.started"]({ kind = "safari" })
T:eq(installed:pendingCount(), 3,
  "unsupported battle variants never queue a mislabeled autosave")

local stale = AutoSaveController.new({
  service = service, checkpoints = checkpoints,
  option = function(key) return options[key] end,
})
stale:onTrigger("wild_battle_start", { contextKey = "wild" })
checkpoints.capability = { canCapture = true, canRestore = true, kind = "overworld" }
local staleResult, staleCode = stale:tick(game)
T:eq(staleResult, false, "battle request is discarded after battle has ended")
T:eq(staleCode, "stale_trigger", "expired battle request is explicit")
T:eq(stale:pendingCount(), 0, "expired battle request cannot save later overworld state")

T:finish()
