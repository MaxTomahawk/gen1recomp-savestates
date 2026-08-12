local Test = dofile("tests/testlib.lua")
local T = Test.new("dated history view")

local HistoryFactory = dofile("src/ui/HistoryView.lua")

local Font = {
  width = function(text) return #tostring(text or "") * 8 end,
  draw = function() end,
  drawCode = function() end,
}
local closed = 0
local mod = { ui = { Font = Font, ListMenu = {} } }
function mod.ui.ListMenu.new(game, title, items, opts)
  local view = { game = game, title = title, items = items, opts = opts or {} }
  function view:close() closed = closed + 1 end
  return view
end

local pressed = {}
local game = { input = {} }
function game.input:wasPressed(button) return pressed[button] == true end

local chosen
local items = {
  { label = "LATEST", value = { metadata = { createdAt = 300 } } },
  { label = "EARLIER", value = { metadata = { createdAt = 250 } } },
  { label = "YESTERDAY", value = { metadata = { createdAt = 150 } } },
  { label = "OLDER", value = { metadata = { createdAt = 100 } } },
}
local dates = { [300] = "11-08-2026", [250] = "11-08-2026",
  [150] = "09-08-2026", [100] = "09-08-2026" }

local History = HistoryFactory({ visualRows = 7 })
local view = History.new(mod, game, "QUICK SAVES", items, {
  dateFor = function(item) return dates[item.value.metadata.createdAt] end,
  onChoose = function(item) chosen = item end,
})

T:eq(#view.items, 4,
  "date grouping never inserts selectable pseudo-items into state history")
local visual = view:visibleRows()
T:eq(visual[1].kind, "header", "the newest date is a visual header")
T:eq(visual[1].text, "11-08-2026", "date header uses the supplied device formatter")
T:eq(visual[2].kind, "state", "the state follows its date header")
T:eq(visual[2].itemIndex, 1, "the first state remains selection index one")
T:eq(visual[4].kind, "header", "a changed date starts a second visual group")
T:eq(visual[4].text, "09-08-2026", "second group has its own date header")
local modern = view:modernModel()
T:eq(modern.rows[1].header, true,
  "Modern UI receives the date as a non-interactive heading")
T:eq(modern.rows[2].label, "LATEST",
  "Modern UI receives the same source-owned first state")
T:eq(modern.index, 2,
  "Modern UI selection maps the state cursor past the heading")

pressed.down = true
view:update()
T:eq(view.index, 2, "one Down moves directly to the next state")
T:eq(view:modernModel().index, 3,
  "Modern UI selection continues to skip non-selectable headings")
pressed.down = nil
pressed.a = true
view:update()
T:check(chosen == items[2], "A selects the state, never the intervening date header")
pressed.a = nil
pressed.b = true
view:update()
T:eq(closed, 1, "B closes through the public screen lifecycle")

T:finish()
