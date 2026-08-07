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

local unsupported, unsupportedCode = controller:onTrigger(
  "trainer_battle_start", { contextKey = "trainer:1" })
T:eq(unsupported, false, "unproven battle trigger is not faked")
T:eq(unsupportedCode, "unsupported_trigger", "unproven trigger is explicit")

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
T:eq(eventHandlers["battle.started"], nil,
  "installation does not subscribe to unsupported battle capture")

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

options.auto_after_battle = true
eventHandlers["battle.ended"]({ result = "win" })
T:eq(installed:pendingCount(), 1, "enabled battle end queues for overworld return")

T:finish()
