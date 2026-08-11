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
local iconDraws = {}
local mod = { ui = {
  Font = Font,
  ListMenu = {},
  PokemonIcon = {
    draw = function(gameArg, mon, x, y, opts)
      iconDraws[#iconDraws + 1] = {
        game = gameArg, mon = mon, x = x, y = y, opts = opts,
      }
      return mon.species ~= nil
    end,
  },
} }
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
    { species = "PIKACHU", name = "SPARKY", level = 22, hp = 45, maxHp = 57 },
    { species = "BUTTERFREE", name = "FAINTED", level = 18, hp = 0, maxHp = 46 },
  },
})

T:eq(#detail.items, 0,
  "details use no selectable ListMenu rows")
T:eq(detail.index, 1,
  "details cursor selects whole Pokemon entries only")
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
T:eq(detail.blocks[3].lines[2], "LV22 HP 45/57",
  "Pokemon block keeps Party-style level and HP in one selectable entry")
T:eq(detail.blocks[4].lines[2], "LV18 HP 0/46",
  "fainted Pokemon keeps exact captured HP")
local modern = detail:modernModel()
T:eq(modern.rows[1].label, "LOCATION",
  "Modern UI receives the consolidated metadata field")
T:eq(modern.rows[1].value, "CERULEAN GYM",
  "Modern UI owns collision-safe field presentation")
T:eq(modern.rows[3].label, "SPARKY",
  "Modern UI receives one source-owned Pokemon row")
T:eq(modern.rows[3].value, "LV22 HP 45/57",
  "Modern UI receives captured level and HP")
T:eq(modern.rows[3].species, "PIKACHU",
  "Modern UI can resolve the same composable species icon")
T:eq(modern.index, 3,
  "Modern UI selection maps to the selected Pokemon after metadata rows")

detail:draw()
T:eq(drawn[1].text, "STATE DETAILS",
  "read-only view draws one consolidated title")
T:eq(iconDraws[1].mon.species, "PIKACHU",
  "details delegate species icons to the public engine presentation helper")
T:eq(iconDraws[1].opts.selected, true,
  "the selected party preview receives native icon animation semantics")

pressed.down = true
detail:update()
T:eq(detail.index, 2, "down selects the next whole Pokemon entry")
T:eq(detail:modernModel().index, 4,
  "Modern UI cursor follows the second Pokemon as one logical row")
pressed.down = nil
pressed.b = true
detail:update()
T:eq(closed, 1, "B closes through the public ListMenu lifecycle")

T:finish()
