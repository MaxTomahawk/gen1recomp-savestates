local Test = dofile("tests/testlib.lua")
local T = Test.new("start menu integration")
local StartMenu = dofile("src/ui/StartMenuIntegration.lua")

local installed
local pushes, saves = {}, 0
local mod = {
  hooks = {
    wrap = function(_, name, callback)
      T:eq(name, "ui.start_menu.items", "integration uses the public START hook")
      installed = callback
      return function() end
    end,
  },
  ui = {},
}
function mod.ui.insertBefore(items, anchor, item)
  local at = #items + 1
  for index, candidate in ipairs(items) do
    if candidate.label == anchor then at = index break end
  end
  table.insert(items, at, item)
  return items
end
function mod.ui.push(game, screen)
  pushes[#pushes + 1] = { game = game, screen = screen }
end

local game = {}
local service = { quickSave = function(_, target)
  T:check(target == game, "QUICKSAVE forwards the live game")
  saves = saves + 1
end }
StartMenu.install(mod, service, "SavestatesRoot")
T:eq(type(installed), "function", "START integration installs one wrapper")

local vanilla = {
  { label = "SAVE" }, { label = "OPTION" }, { label = "QUIT" },
}
local function downstream(targetGame, items)
  T:check(targetGame == game, "wrapper forwards game through downstream chain")
  return mod.ui.insertBefore(items, "OPTION", { label = "OTHER MOD" })
end
local decorated = installed(downstream, game, vanilla)
local labels = {}
for index, item in ipairs(decorated) do labels[index] = item.label end
T:eq(#labels, 6, "two Save States rows coexist with another decorator")
T:eq(labels[1], "SAVE", "vanilla SAVE remains untouched")
T:eq(labels[2], "OTHER MOD", "other mod row survives")
T:eq(labels[3], "QUICKSAVE", "QUICKSAVE anchors before OPTION")
T:eq(labels[4], "STATES", "STATES follows QUICKSAVE")
T:eq(labels[5], "OPTION", "vanilla OPTION remains after Save States rows")
T:eq(labels[6], "QUIT", "later vanilla rows preserve order")

decorated[3].onSelect()
T:eq(saves, 1, "QUICKSAVE invokes service exactly once")
decorated[4].onSelect()
T:eq(pushes[1].screen, "SavestatesRoot", "STATES opens the registered root screen")

local marker = "downstream-non-table"
T:eq(installed(function() return marker end, game, {}), marker,
  "non-table downstream result is preserved without mutation")

T:finish()
