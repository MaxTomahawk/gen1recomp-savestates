local Test = dofile("tests/testlib.lua")
local T = Test.new("title menu integration")
local TitleMenu = dofile("src/ui/TitleMenuIntegration.lua")

local installed
local pushes = {}
local mod = {
  hooks = {
    wrap = function(_, name, callback)
      T:eq(name, "ui.title_menu.items", "integration uses the public title hook")
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
function mod.ui.push(game, screen, opts)
  pushes[#pushes + 1] = { game = game, screen = screen, opts = opts }
end

local game = {}
TitleMenu.install(mod, "SavestatesRoot")
T:eq(type(installed), "function", "title integration installs one wrapper")

local vanilla = {
  { label = "CONTINUE" }, { label = "NEW GAME" },
  { label = "OPTION" }, { label = "EXIT GAME" },
}
local function downstream(targetGame, items)
  T:eq(targetGame, game, "wrapper forwards the live title game")
  return mod.ui.insertBefore(items, "NEW GAME", { label = "OTHER TITLE MOD" })
end
local decorated = installed(downstream, game, vanilla)
local labels = {}
for index, item in ipairs(decorated) do labels[index] = item.label end
T:eq(#labels, 6, "Save States coexists with another title-menu decorator")
T:eq(labels[1], "CONTINUE", "ordinary CONTINUE remains first")
T:eq(labels[2], "OTHER TITLE MOD", "downstream title item survives")
T:eq(labels[3], "SAVE STATES", "Save States anchors before NEW GAME")
T:eq(labels[4], "NEW GAME", "ordinary New Game remains after Save States")
T:eq(labels[5], "OPTION", "ordinary Option remains intact")
T:eq(labels[6], "EXIT GAME", "ordinary Exit remains intact")

decorated[3].onSelect()
T:eq(pushes[1].game, game, "title action forwards the title game")
T:eq(pushes[1].screen, "SavestatesRoot", "title action reuses the registered root")
T:eq(pushes[1].opts.context, "title",
  "title action enters the selected-playthrough manager context")

local marker = "downstream-non-table"
T:eq(installed(function() return marker end, game, {}), marker,
  "non-table downstream result is preserved without mutation")

T:finish()
