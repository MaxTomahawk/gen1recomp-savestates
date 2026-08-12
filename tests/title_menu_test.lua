local Test = dofile("tests/testlib.lua")
local T = Test.new("title menu integration")
local TitleMenu = dofile("src/ui/TitleMenuIntegration.lua")

local installed
local pushes = {}
local resumed = {}
local latestCalls = 0
local latest = { metadata = { id = "q00000042" } }
local game = {}
local service = {
  titleLatestResumeCandidate = function(_, targetGame)
    latestCalls = latestCalls + 1
    T:eq(targetGame, game, "latest policy receives the title game")
    return latest
  end,
  resumeTitleState = function(_, targetGame, id)
    resumed[#resumed + 1] = { game = targetGame, id = id }
  end,
}
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

TitleMenu.install(mod, service, "SavestatesRoot", function() return true end)
T:eq(type(installed), "function", "title integration installs one wrapper")

local vanilla = {
  { label = "CONTINUE", onSelect = function() end }, { label = "NEW GAME" },
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

decorated[1].onSelect()
T:eq(latestCalls, 1, "enabled title policy evaluates the selected history once")
T:eq(resumed[1] and resumed[1].game, game,
  "newer savestate CONTINUE keeps the title game")
T:eq(resumed[1] and resumed[1].id, "q00000042",
  "newer savestate replaces only CONTINUE callback")

decorated[3].onSelect()
T:eq(pushes[1].game, game, "title action forwards the title game")
T:eq(pushes[1].screen, "SavestatesRoot", "title action reuses the registered root")
T:eq(pushes[1].opts.context, "title",
  "title action enters the selected-playthrough manager context")

local marker = "downstream-non-table"
T:eq(installed(function() return marker end, game, {}), marker,
  "non-table downstream result is preserved without mutation")

-- A savestate-only playthrough has no native CONTINUE row.  The integration
-- may add one only after the service has selected a valid existing state.
latest = { metadata = { id = "s01_00000043" } }
local noNormal = installed(function(_, items) return items end, game, {
  { label = "NEW GAME" }, { label = "OPTION" },
})
T:eq(noNormal[1].label, "CONTINUE",
  "savestate-only selected playthrough gets a title CONTINUE row")
noNormal[1].onSelect()
T:eq(resumed[#resumed] and resumed[#resumed].id, "s01_00000043",
  "savestate-only CONTINUE resumes the selected checkpoint")

local disabled
local disabledMod = {
  hooks = { wrap = function(_, _, callback) disabled = callback end },
  ui = mod.ui,
}
TitleMenu.install(disabledMod, service, "SavestatesRoot", function() return false end)
local vanillaContinueCalls = 0
local disabledItems = disabled(function(_, items) return items end, game, {
  { label = "CONTINUE", onSelect = function() vanillaContinueCalls = vanillaContinueCalls + 1 end },
  { label = "NEW GAME" },
})
disabledItems[1].onSelect()
T:eq(vanillaContinueCalls, 1,
  "disabled Continue Latest leaves the exact vanilla CONTINUE callback intact")
T:eq(latestCalls, 2,
  "disabled Continue Latest does not inspect selected savestate history")

T:finish()
