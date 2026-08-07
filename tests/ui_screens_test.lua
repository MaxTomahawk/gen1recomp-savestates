local Test = dofile("tests/testlib.lua")
local T = Test.new("native state screens")
local Time = dofile("src/util/Time.lua")
local ScreenFactory = dofile("src/ui/ScreenRegistry.lua")({ Time = Time })

local registered, pushes = {}, {}
local mod = {
  content = { screens = {} },
  ui = { ListMenu = {}, NamingScreen = {} },
  options = { values = {
    quick_history = 5, auto_history = 20,
    save_notifications = true, load_notifications = false,
  } },
}
function mod.content.screens:register(id, factory) registered[id] = factory end
function mod.ui.ListMenu.new(game, title, items, opts)
  local menu = { game = game, title = title, items = items, opts = opts or {}, closeCount = 0 }
  function menu:close() self.closeCount = self.closeCount + 1 end
  function menu:removeCurrent() table.remove(self.items, self.index or 1) end
  return menu
end
function mod.ui.NamingScreen.new(game, opts)
  return { game = game, naming = true, opts = opts }
end
function mod.ui.push(game, id, opts)
  pushes[#pushes + 1] = { game = game, id = id, opts = opts }
end
function mod.options:get(key) return self.values[key] end

local calls = {}
local service = {
  summaryValue = {
    quickCount = 2, autoCount = 3, slotCount = 1, slotCapacity = 10,
    undoAvailable = false,
  },
  quickRows = {}, autoRows = {},
  slotRows = {},
}
for slot = 1, 10 do service.slotRows[slot] = { slot = slot, occupied = false } end
service.slotRows[2] = {
  slot = 2, occupied = true, available = true,
  metadata = { id = "s02_00000001", label = "BEFORE MISTY",
    locationName = "CERULEAN GYM", createdAt = 900 },
}
function service:summary() return self.summaryValue end
function service:listStates(_, class)
  return class == "quick" and self.quickRows or self.autoRows
end
function service:listSlots() return self.slotRows end
function service:quickSave() calls[#calls + 1] = "quickSave" return true end
function service:undoLastLoad() calls[#calls + 1] = "undo" return true end
function service:loadState(_, id) calls[#calls + 1] = "load:" .. id return true end
function service:deleteState(_, id) calls[#calls + 1] = "delete:" .. id return true end
function service:saveSlot(_, slot) calls[#calls + 1] = "saveSlot:" .. slot return true end
function service:loadSlot(_, slot) calls[#calls + 1] = "loadSlot:" .. slot return true end
function service:deleteSlot(_, slot) calls[#calls + 1] = "deleteSlot:" .. slot return true end
function service:renameSlot(_, slot, name)
  calls[#calls + 1] = "rename:" .. slot .. ":" .. name
  return { metadata = { id = "s02_00000002", slot = slot, label = name,
    locationName = "CERULEAN GYM", createdAt = 1000 } }
end
function service:pinToSlot(_, id, slot)
  calls[#calls + 1] = "pin:" .. id .. ":" .. slot return true
end

local ids = ScreenFactory.install(mod, service, function() return 1000 end)
T:eq(type(ids), "table", "screen installation returns stable ids")
for _, id in pairs(ids) do
  T:check(registered[id] ~= nil, "registered native screen " .. id)
end

local game = {}
local root = registered[ids.root].new(game)
T:eq(root.title, "SAVE STATES", "root screen has native product title")
T:eq(root.items[1].label, "QUICK SAVES", "root begins with quick history")
T:eq(root.items[1].right, "2", "root reports quick history count")
T:eq(root.items[2].label, "AUTO SAVES", "root includes auto history")
T:eq(root.items[3].label, "SAVE SLOTS", "root includes permanent slots")
T:eq(root.items[3].right, "1/10", "root reports occupied slot capacity")
T:eq(root.items[4].label, "SETTINGS", "root omits unavailable undo cleanly")
root.items[1].onSelect()
T:eq(pushes[#pushes].id, ids.history, "quick row opens registered history screen")
T:eq(pushes[#pushes].opts.class, "quick", "quick row passes history class")

service.summaryValue.undoAvailable = true
root = registered[ids.root].new(game)
T:eq(root.items[4].label, "UNDO LAST LOAD", "root exposes undo when recovery exists")
root.items[4].onSelect()
T:eq(root.closeCount, 1, "undo closes root to reach safe overworld")
T:eq(calls[#calls], "undo", "undo row invokes service")

local emptyQuick = registered[ids.history].new(game, { class = "quick", parent = root })
T:eq(emptyQuick.items[1].label, "NO QUICK SAVES YET.",
  "empty quick history is useful, not blank")

service.quickRows = {
  { available = true, status = "compatible", metadata = {
      id = "q00000002", locationName = "CERULEAN GYM", createdAt = 1000,
    } },
  { available = false, status = "corrupt_metadata", metadata = {
      id = "q00000001", locationName = "PALLET TOWN", createdAt = 900,
    } },
}
local history = registered[ids.history].new(game, { class = "quick", parent = root })
T:eq(history.title, "QUICK SAVES", "quick history has native title")
T:eq(history.items[1].right, "NOW", "valid state displays relative age")
T:eq(history.items[2].right, "BAD", "unavailable state stays visible and marked")
history.items[1].onSelect(history.items[1], history)
T:eq(pushes[#pushes].id, ids.actions, "state row opens action menu")

local action = registered[ids.actions].new(game, {
  row = service.quickRows[1], parents = { history, root },
})
T:eq(action.items[1].label, "LOAD", "available state action begins with load")
T:eq(action.items[2].label, "PIN TO SLOT", "available state can pin permanently")
action.items[1].onSelect()
T:eq(action.closeCount, 1, "load closes action menu")
T:eq(history.closeCount, 1, "load closes history menu")
T:eq(root.closeCount, 2, "load closes root menu after history")
T:eq(calls[#calls], "load:q00000002", "load action invokes selected state id")

local unavailableAction = registered[ids.actions].new(game, {
  row = service.quickRows[2], parents = { history, root },
})
T:eq(unavailableAction.items[1].label, "DELETE",
  "unavailable state offers safe cleanup instead of load")

local slotsScreen = registered[ids.slots].new(game, { parent = root })
T:eq(#slotsScreen.items, 10, "slot screen always renders ten rows")
T:eq(slotsScreen.items[1].right, "EMPTY", "empty slot is explicit")
T:eq(slotsScreen.items[2].right, "BEFORE MISTY", "occupied slot shows custom label")
slotsScreen.items[1].onSelect(slotsScreen.items[1], slotsScreen)
T:eq(pushes[#pushes].id, ids.slotActions, "slot row opens slot action screen")

local emptySlotAction = registered[ids.slotActions].new(game, {
  row = service.slotRows[1], parents = { slotsScreen, root },
})
T:eq(emptySlotAction.items[1].label, "SAVE HERE", "empty slot offers save")
emptySlotAction.items[1].onSelect()
T:eq(calls[#calls], "saveSlot:1", "empty slot invokes stable save action")

local occupiedSlotAction = registered[ids.slotActions].new(game, {
  row = service.slotRows[2], parents = { slotsScreen, root }, slotMenu = slotsScreen,
})
local occupiedLabels = {}
for i, item in ipairs(occupiedSlotAction.items) do occupiedLabels[i] = item.label end
T:eq(occupiedLabels[1], "LOAD", "occupied slot can load")
T:eq(occupiedLabels[2], "OVERWRITE", "occupied slot can overwrite")
T:eq(occupiedLabels[3], "RENAME", "occupied slot can rename")
T:eq(occupiedLabels[4], "DELETE", "occupied slot can delete")
occupiedSlotAction.items[3].onSelect()
T:eq(pushes[#pushes].id, ids.rename, "rename action opens native naming screen")
local rename = registered[ids.rename].new(game, pushes[#pushes].opts)
T:eq(rename.naming, true, "rename screen uses public native NamingScreen")
rename.opts.onDone("MISTY")
T:eq(calls[#calls], "rename:2:MISTY", "naming result updates selected slot")

local settings = registered[ids.settings].new(game, { parent = root })
T:eq(settings.title, "STATE SETTINGS", "settings screen is native")
T:eq(settings.items[1].right, "5", "settings shows current quick limit")
T:eq(settings.items[4].right, "OFF", "settings shows notification toggle")
T:check(settings.opts.footer:find("MODS", 1, true) ~= nil,
  "settings explains the public manager edit path")

T:finish()
