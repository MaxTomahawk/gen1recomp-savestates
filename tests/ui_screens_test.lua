local Test = dofile("tests/testlib.lua")
local T = Test.new("native state screens")
local Time = dofile("src/util/Time.lua")
local Details = dofile("src/ui/StateDetailsView.lua")()
local ScreenFactory = dofile("src/ui/ScreenRegistry.lua")({
  Time = Time,
  Details = Details,
})

local registered, pushes = {}, {}
local mod = {
  content = { screens = {} },
  ui = { ListMenu = {}, NamingScreen = {}, TextBox = {}, Font = {} },
  options = { values = {
    quick_history = 5, auto_history = 20,
    auto_location = true, auto_trainer_battle = true,
    auto_wild_battle = true, auto_after_battle = false,
    auto_before_warp = false,
    save_notifications = true, load_notifications = false,
    history_time = "play_time",
    debug_logging = false,
  } },
}
local fontMetricCalls = 0
function mod.ui.Font.width(text)
  fontMetricCalls = fontMetricCalls + 1
  return #tostring(text or "") * 8
end
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
function mod.ui.TextBox.new(game, text, onDone, opts)
  return { game = game, text = text, onDone = onDone, opts = opts or {} }
end
function mod.ui.push(game, id, opts)
  pushes[#pushes + 1] = { game = game, id = id, opts = opts }
end
function mod.options:get(key) return self.values[key] end

local function rightFor(menu, label)
  for _, item in ipairs(menu.items or {}) do
    if item.label == label then return item.right end
  end
end

local function detailValue(view, label)
  for _, block in ipairs(view.blocks or {}) do
    if block.kind == "field" and block.label == label then
      return block.value
    end
  end
end

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
function service:inspectState(_, id)
  calls[#calls + 1] = "inspect:" .. id
  if self.inspectOverrides and self.inspectOverrides[id] then
    return self.inspectOverrides[id]
  end
  local function find(rows)
    for _, row in ipairs(rows) do
      if row.metadata and row.metadata.id == id then return row end
    end
  end
  local row = find(self.quickRows) or find(self.autoRows)
  if not row then
    for _, candidate in ipairs(self.slotRows) do
      if candidate.metadata and candidate.metadata.id == id then row = candidate break end
    end
  end
  return row
end
function service:quickSave() calls[#calls + 1] = "quickSave" return true end
function service:undoLastLoad() calls[#calls + 1] = "undo" return true end
function service:loadState(_, id) calls[#calls + 1] = "load:" .. id return true end
function service:deleteState(_, id)
  calls[#calls + 1] = "delete:" .. id
  self.summaryValue.quickCount = self.summaryValue.quickCount - 1
  return true
end
function service:saveSlot(_, slot) calls[#calls + 1] = "saveSlot:" .. slot return true end
function service:loadSlot(_, slot) calls[#calls + 1] = "loadSlot:" .. slot return true end
function service:deleteSlot(_, slot)
  calls[#calls + 1] = "deleteSlot:" .. slot
  self.summaryValue.slotCount = self.summaryValue.slotCount - 1
  return true
end
function service:renameSlot(_, slot, name)
  calls[#calls + 1] = "rename:" .. slot .. ":" .. name
  return { metadata = { id = "s02_00000002", slot = slot, label = name,
    locationName = "CERULEAN GYM", createdAt = 1000 } }
end
function service:pinToSlot(_, id, slot)
  calls[#calls + 1] = "pin:" .. id .. ":" .. slot
  if not self.slotRows[slot].occupied then
    self.summaryValue.slotCount = self.summaryValue.slotCount + 1
  end
  self.slotRows[slot] = {
    slot = slot, occupied = true, available = true,
    metadata = { id = ("s%02d_pinned"):format(slot), label = "PINNED",
      locationName = "CERULEAN GYM", createdAt = 1000 },
  }
  return true
end
function service:titleSummary()
  return {
    quickCount = self.summaryValue.quickCount,
    autoCount = self.summaryValue.autoCount,
    slotCount = self.summaryValue.slotCount,
    slotCapacity = self.summaryValue.slotCapacity,
    undoAvailable = false,
  }
end
function service:titleListStates(_, class) return self:listStates(nil, class) end
function service:titleListSlots() return self:listSlots() end
function service:titleInspectState(_, id) return self:inspectState(nil, id) end
function service:resumeTitleState(_, id)
  calls[#calls + 1] = "titleResume:" .. id
  return true
end
function service:titlePinToSlot(_, id, slot)
  calls[#calls + 1] = "titlePin:" .. id .. ":" .. slot
  return true
end
function service:titleRenameSlot(_, slot, name)
  calls[#calls + 1] = "titleRename:" .. slot .. ":" .. name
  return { metadata = { id = "s02_title", slot = slot, label = name,
    locationName = "CERULEAN GYM", createdAt = 1000 } }
end
function service:titleDeleteState(_, id)
  calls[#calls + 1] = "titleDelete:" .. id
  return true
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

local battleRoot = registered[ids.root].new(game, { context = "battle" })
T:eq(battleRoot.items[1].label, "QUICKSAVE",
  "battle manager exposes an explicit safe-boundary quicksave action")
battleRoot.items[1].onSelect()
T:eq(calls[#calls], "quickSave", "battle quicksave remains source-owned")
root.items[1].onSelect()
T:eq(pushes[#pushes].id, ids.history, "quick row opens registered history screen")
T:eq(pushes[#pushes].opts.class, "quick", "quick row passes history class")

local titleRoot = registered[ids.root].new(game, { context = "title" })
T:eq(titleRoot.items[1].label, "QUICK SAVES",
  "title manager reuses the normal history root")
T:eq(titleRoot.items[4].label, "SETTINGS",
  "title manager never offers runtime-only undo recovery")
titleRoot.items[1].onSelect()
T:eq(pushes[#pushes].opts.context, "title",
  "title history remains in the selected-playthrough context")

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
      trigger = "manual", stateKind = "battle",
      preview = {
        playTime = 16620, badgeCount = 1, badgeTotal = 8,
        party = { { name = "SPARKY", level = 22, hp = 45, maxHp = 57 } },
      },
    } },
  { available = false, status = "corrupt_metadata", metadata = {
      id = "q00000001", locationName = "PALLET TOWN", createdAt = 900,
    } },
}
local history = registered[ids.history].new(game, { class = "quick", parent = root })
T:eq(history.title, "QUICK SAVES", "quick history has native title")
T:eq(history.items[1].right, "04:37", "default history displays captured play time")
T:eq(history.items[2].right, "BAD", "unavailable state stays visible and marked")
mod.options.values.history_time = "date_time"
local dateHistory = registered[ids.history].new(game, { class = "quick", parent = root })
T:eq(dateHistory.items[1].right, Time.historyDate(1000),
  "history DATE/TIME mode uses captured timestamp")
mod.options.values.history_time = "age"
local ageHistory = registered[ids.history].new(game, { class = "quick", parent = root })
T:eq(ageHistory.items[1].right, "NOW", "history AGE mode remains available")
mod.options.values.history_time = "play_time"
local legacyHistory = registered[ids.history].new(game, {
  class = "quick", parent = root,
})
service.quickRows = {
  { available = true, metadata = {
      id = "qlegacy", locationName = "PALLET TOWN", createdAt = 900,
    } },
}
legacyHistory = registered[ids.history].new(game, { class = "quick", parent = root })
T:eq(legacyHistory.items[1].right, "1m",
  "previewless legacy states fall back to capture age in PLAY TIME mode")
service.quickRows = {
  { available = true, status = "compatible", metadata = {
      id = "q00000002", locationName = "CERULEAN GYM", createdAt = 1000,
      trigger = "manual", stateKind = "battle",
      preview = {
        playTime = 16620, badgeCount = 1, badgeTotal = 8,
        party = { { name = "SPARKY", level = 22, hp = 45, maxHp = 57 } },
      },
    } },
  { available = false, status = "corrupt_metadata", metadata = {
      id = "q00000001", locationName = "PALLET TOWN", createdAt = 900,
    } },
}
history.items[1].onSelect(history.items[1], history)
T:eq(pushes[#pushes].id, ids.actions, "state row opens action menu")

local action = registered[ids.actions].new(game, {
  row = service.quickRows[1], parents = { history, root },
})
T:eq(action.items[1].label, "LOAD", "available state keeps load immediately visible")
T:eq(action.items[2].label, "PIN TO SLOT", "available state keeps pin immediately visible")
T:eq(action.items[3].label, "DETAILS", "state preview opens a dedicated detail screen")
T:eq(action.items[4].label, "DELETE", "state cleanup stays on the action screen")
T:eq(action.index, 1, "action cursor begins on load without scrolling")
if action.items[1].label ~= "LOAD" then T:finish() end
local detail
if type(action.items[3].onSelect) == "function" then
  action.items[3].onSelect()
  T:eq(pushes[#pushes].id, ids.details, "details action opens a registered native detail screen")
  detail = registered[ids.details].new(game, pushes[#pushes].opts)
  T:eq(#detail.items, 0,
    "state details have no selectable ListMenu rows")
  T:eq(detail.index, nil,
    "state details have no cursor on continuation lines")
  T:eq(detailValue(detail, "LOCATION"), "CERULEAN GYM",
    "location remains one readable logical block")
  T:eq(detailValue(detail, "CREATED"), Time.absolute(1000),
    "detail screen shows useful absolute creation date and time")
  local mon = detail.blocks[#detail.blocks]
  T:eq(mon.kind, "pokemon",
    "each party member remains one logical block")
  T:eq(mon.lines[1], "SPARKY",
    "each party block starts with its captured name")
  T:eq(mon.lines[2], "LV22   HP 45/57",
    "each party block always has a second level and HP line")
  T:check(fontMetricCalls > 0,
    "detail layout uses the public Font.width metric instead of character guesses")
end

local titleHistory = { close = function(self) self.closeCount = (self.closeCount or 0) + 1 end }
local titleAction = registered[ids.actions].new(game, {
  row = service.quickRows[1], parents = { titleHistory, titleRoot }, context = "title",
})
T:eq(titleAction.items[1].label, "LOAD", "title action exposes compatible load")
T:eq(titleAction.items[2].label, "PIN TO SLOT", "title action retains durable pinning")
titleAction.items[1].onSelect()
T:eq(calls[#calls], "titleResume:q00000002",
  "title load uses checkpoint resume rather than live restore")

service.inspectOverrides = {
  qwarn = {
    available = true,
    warnings = { "engine_version_mismatch" },
    metadata = {
      id = "qwarn", locationName = "CERULEAN GYM", createdAt = 1000,
      trigger = "manual", stateKind = "battle",
    },
  },
}
local warningAction = registered[ids.actions].new(game, {
  row = {
    metadata = { id = "qwarn" },
  },
  parents = { history, root },
})
if type(warningAction.items[3].onSelect) == "function" then
  warningAction.items[3].onSelect()
  detail = registered[ids.details].new(game, pushes[#pushes].opts)
  T:eq(detailValue(detail, "STATUS"), "WARN",
    "detail screen marks soft engine compatibility warnings before load")
end

local pinAction = registered[ids.actions].new(game, {
  row = service.quickRows[1], parents = { history, root },
})
pinAction.items[2].onSelect()
T:eq(pushes[#pushes].id, ids.pinPicker, "pin action opens the permanent-slot picker")
local pinPicker = registered[ids.pinPicker].new(game, pushes[#pushes].opts)
pinPicker.items[1].onSelect()
T:eq(calls[#calls], "pin:q00000002:1", "pin picker copies into selected slot")
T:eq(root.items[3].right, "2/10", "pinning refreshes occupied-slot root count")
local callsBeforeOccupiedPin = #calls
pinPicker.items[2].onSelect()
T:eq(pushes[#pushes].id, ids.overwriteConfirm,
  "pinning into an occupied slot requests overwrite confirmation")
local overwriteConfirm = registered[ids.overwriteConfirm].new(
  game, pushes[#pushes].opts)
T:eq(overwriteConfirm.opts.defaultNo, true,
  "slot overwrite confirmation defaults to NO")
overwriteConfirm.opts.choice(false)
T:eq(#calls, callsBeforeOccupiedPin,
  "cancelled occupied-slot pin leaves the permanent slot untouched")
pinPicker.items[2].onSelect()
overwriteConfirm = registered[ids.overwriteConfirm].new(game, pushes[#pushes].opts)
overwriteConfirm.opts.choice(true)
T:eq(calls[#calls], "pin:q00000002:2",
  "confirmed occupied-slot pin invokes the requested copy")

action.items[1].onSelect()
T:eq(action.closeCount, 1, "load closes action menu")
T:eq(history.closeCount, 1, "load closes history menu")
T:eq(root.closeCount, 2, "load closes root menu after history")
T:eq(calls[#calls], "load:q00000002", "load action invokes selected state id")

local unavailableAction = registered[ids.actions].new(game, {
  row = service.quickRows[2], parents = { history, root },
})
T:eq(unavailableAction.items[1].label, "DETAILS",
  "unavailable state still exposes readable diagnostics")
if type(unavailableAction.items[1].onSelect) == "function" then
  unavailableAction.items[1].onSelect()
  detail = registered[ids.details].new(game, pushes[#pushes].opts)
  T:eq(detailValue(detail, "STATUS"), "CORRUPT_M.",
    "unavailable detail exposes a conservative compatibility code")
end
T:eq(unavailableAction.items[2].label, "DELETE",
  "unavailable state offers safe cleanup instead of load")
history.index = 2
local callsBeforeDelete = #calls
unavailableAction.items[2].onSelect()
T:eq(pushes[#pushes].id, ids.deleteConfirm,
  "history delete opens the registered native confirmation")
local deleteConfirm = registered[ids.deleteConfirm].new(game, pushes[#pushes].opts)
T:eq(deleteConfirm.opts.defaultNo, true, "delete confirmation defaults to NO")
deleteConfirm.opts.choice(false)
T:eq(#calls, callsBeforeDelete, "cancelled delete does not mutate state")
T:eq(unavailableAction.closeCount, 0, "cancelled delete keeps action menu open")
unavailableAction.items[2].onSelect()
deleteConfirm = registered[ids.deleteConfirm].new(game, pushes[#pushes].opts)
deleteConfirm.opts.choice(true)
T:eq(calls[#calls], "delete:q00000001", "confirmed history delete invokes service")
T:eq(unavailableAction.closeCount, 1, "confirmed history delete closes action menu")
T:eq(#history.items, 1, "confirmed history delete removes the visible row")
T:eq(root.items[1].right, "1", "history deletion refreshes root history count")

local slotsScreen = registered[ids.slots].new(game, { parent = root })
T:eq(#slotsScreen.items, 10, "slot screen always renders ten rows")
T:eq(slotsScreen.items[1].right, "PINNED", "newly pinned slot stays visible")
T:eq(slotsScreen.items[2].right, "PINNED",
  "confirmed pin refreshes the occupied slot label")
T:eq(slotsScreen.items[3].right, "EMPTY", "empty slot is explicit")
slotsScreen.items[3].onSelect(slotsScreen.items[3], slotsScreen)
T:eq(pushes[#pushes].id, ids.slotActions, "slot row opens slot action screen")

local emptySlotAction = registered[ids.slotActions].new(game, {
  row = service.slotRows[3], parents = { slotsScreen, root },
})
T:eq(emptySlotAction.items[1].label, "SAVE HERE", "empty slot offers save")
emptySlotAction.items[1].onSelect()
T:eq(calls[#calls], "saveSlot:3", "empty slot invokes stable save action")

local titleEmptySlotAction = registered[ids.slotActions].new(game, {
  row = service.slotRows[3], parents = { slotsScreen, titleRoot }, context = "title",
})
T:eq(titleEmptySlotAction.items[1].label, "CANCEL",
  "title empty slots never offer a live checkpoint capture")

local occupiedSlotAction = registered[ids.slotActions].new(game, {
  row = service.slotRows[2], parents = { slotsScreen, root }, slotMenu = slotsScreen,
})
local occupiedLabels = {}
for i, item in ipairs(occupiedSlotAction.items) do occupiedLabels[i] = item.label end
T:eq(occupiedLabels[1], "LOAD", "occupied slot can load")
T:eq(occupiedLabels[2], "OVERWRITE", "occupied slot can overwrite")
T:eq(occupiedLabels[3], "RENAME", "occupied slot can rename")
T:eq(occupiedLabels[4], "DETAILS", "occupied slot exposes capture preview separately")
T:eq(occupiedLabels[5], "DELETE", "occupied slot can delete")
local titleOccupiedSlotAction = registered[ids.slotActions].new(game, {
  row = service.slotRows[2], parents = { slotsScreen, titleRoot }, slotMenu = slotsScreen,
  context = "title",
})
local titleOccupiedLabels = {}
for i, item in ipairs(titleOccupiedSlotAction.items) do
  titleOccupiedLabels[i] = item.label
end
T:eq(titleOccupiedLabels[1], "LOAD", "title occupied slot can resume")
T:eq(titleOccupiedLabels[2], "RENAME", "title occupied slot keeps rename")
T:eq(titleOccupiedLabels[3], "DETAILS", "title occupied slot keeps details")
T:eq(titleOccupiedLabels[4], "DELETE", "title occupied slot keeps deletion")
T:eq(titleOccupiedLabels[5], "CANCEL", "title occupied slot remains dismissible")
titleOccupiedSlotAction.items[1].onSelect()
T:eq(calls[#calls], "titleResume:" .. service.slotRows[2].metadata.id,
  "title slot load delegates to selected checkpoint resume")
local callsBeforeOverwrite = #calls
occupiedSlotAction.items[2].onSelect()
T:eq(pushes[#pushes].id, ids.overwriteConfirm,
  "occupied slot overwrite opens the native confirmation")
overwriteConfirm = registered[ids.overwriteConfirm].new(game, pushes[#pushes].opts)
overwriteConfirm.opts.choice(false)
T:eq(#calls, callsBeforeOverwrite,
  "cancelled slot overwrite does not capture or mutate state")
occupiedSlotAction.items[2].onSelect()
overwriteConfirm = registered[ids.overwriteConfirm].new(game, pushes[#pushes].opts)
overwriteConfirm.opts.choice(true)
T:eq(calls[#calls], "saveSlot:2",
  "confirmed slot overwrite invokes the explicit save action")
root.items[3].right = "STALE"
local slotCallsBeforeDelete = #calls
occupiedSlotAction.items[5].onSelect()
T:eq(pushes[#pushes].id, ids.deleteConfirm,
  "slot delete opens the registered native confirmation")
deleteConfirm = registered[ids.deleteConfirm].new(game, pushes[#pushes].opts)
deleteConfirm.opts.choice(false)
T:eq(#calls, slotCallsBeforeDelete, "cancelled slot delete does not mutate state")
occupiedSlotAction.items[5].onSelect()
deleteConfirm = registered[ids.deleteConfirm].new(game, pushes[#pushes].opts)
deleteConfirm.opts.choice(true)
T:eq(calls[#calls], "deleteSlot:2", "confirmed slot delete invokes service")
T:eq(slotsScreen.items[2].right, "EMPTY", "confirmed slot delete refreshes slot row")
T:eq(root.items[3].right, "1/10", "slot deletion refreshes occupied root count")
occupiedSlotAction.items[3].onSelect()
T:eq(pushes[#pushes].id, ids.rename, "rename action opens native naming screen")
local rename = registered[ids.rename].new(game, pushes[#pushes].opts)
T:eq(rename.naming, true, "rename screen uses public native NamingScreen")
T:eq(rename.opts.maxLen, 12,
  "slot names fit the native screen and the documented BEFORE MISTY label")
rename.opts.onDone("MISTY")
T:eq(calls[#calls], "rename:2:MISTY", "naming result updates selected slot")

local settings = registered[ids.settings].new(game, { parent = root })
T:eq(settings.title, "STATE SETTINGS", "settings screen is native")
T:eq(settings.items[1].right, "5", "settings shows current quick limit")
T:eq(#settings.items, 11, "settings reports every product option")
T:eq(settings.items[3].label, "HISTORY TIME", "settings exposes history time mode")
T:eq(settings.items[3].right, "PLAY TIME", "settings names the default history time mode")
T:eq(settings.items[4].label, "LOCATION ENTRY", "settings shows location autosaves")
T:eq(settings.items[4].right, "ON", "settings shows trigger value")
T:eq(settings.items[8].label, "BEFORE WARP", "settings shows warp autosaves")
T:eq(settings.items[8].right, "OFF", "settings shows disabled trigger value")
T:eq(settings.items[10].right, "OFF", "settings shows load notification toggle")
T:eq(settings.items[11].label, "DEBUG TIMINGS", "settings shows diagnostics option")
T:check(settings.opts.footer:find("MODS", 1, true) ~= nil,
  "settings explains the public manager edit path")

T:finish()
