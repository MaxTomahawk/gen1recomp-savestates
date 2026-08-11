local Test = dofile("tests/testlib.lua")
local T = Test.new("read-only state details view")

local DetailsFactory = dofile("src/ui/StateDetailsView.lua")

local drawn = {}
love = { graphics = {
  setColor = function() end,
  rectangle = function() end,
} }

local Font = {
  width = function(text) return #tostring(text or "") * 8 end,
  draw = function(text, x, y)
    drawn[#drawn + 1] = { text = text, x = x, y = y }
  end,
}

local closed = 0
local mod = { ui = { Font = Font, ListMenu = {} } }
function mod.ui.ListMenu.new(game, title, items)
  local menu = { game = game, title = title, items = items }
  function menu:close() closed = closed + 1 end
  return menu
end

local pressed = {}
local game = { input = {} }
function game.input:wasPressed(button) return pressed[button] == true end

local Details = DetailsFactory({ rowsPerPage = 6 })
local detail = Details.new(mod, game, {
  title = "STATE DETAILS",
  fields = {
    { label = "LOCATION", value = "CERULEAN GYM" },
    { label = "CREATED", value = "2001-09-09 03:46" },
  },
  party = {
    { name = "SPARKY", level = 22, hp = 45, maxHp = 57 },
    { name = "FAINTED", level = 18, hp = 0, maxHp = 46 },
  },
})

T:eq(#detail.items, 0,
  "details use no selectable ListMenu rows")
T:eq(detail.index, nil,
  "details expose no cursor index")
T:eq(detail.blocks[1].kind, "field",
  "each metadata field is one logical block")
T:eq(detail.blocks[1].lines[1], "LOCATION",
  "colliding field keeps its label within one block")
T:eq(detail.blocks[1].lines[2], "CERULEAN GYM",
  "colliding field keeps its value as the block continuation")
T:eq(detail.blocks[3].kind, "pokemon",
  "each Pokemon is one logical block")
T:eq(detail.blocks[3].lines[1], "SPARKY",
  "Pokemon block begins with the captured display name")
T:eq(detail.blocks[3].lines[2], "LV22   HP 45/57",
  "Pokemon block always keeps level and HP on its second line")
T:eq(detail.blocks[4].lines[2], "LV18   HP 0/46",
  "fainted Pokemon remains a two-line block with exact captured HP")
T:eq(#detail.pages, 2,
  "pagination never splits a logical field or Pokemon block")

detail:draw()
T:eq(drawn[1].text, "STATE DETAILS",
  "read-only view draws one consolidated title")
for _, row in ipairs(drawn) do
  T:check(row.text ~= "▶" and row.text ~= ">",
    "read-only detail view never draws a selection cursor")
end

pressed.right = true
detail:update()
T:eq(detail.page, 2, "right advances one details page")
pressed.right = nil
pressed.left = true
detail:update()
T:eq(detail.page, 1, "left returns one details page")
pressed.left = nil
pressed.b = true
detail:update()
T:eq(closed, 1, "B closes through the public ListMenu lifecycle")

T:finish()
