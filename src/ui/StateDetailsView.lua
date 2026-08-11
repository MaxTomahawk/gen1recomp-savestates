local StateDetailsView = {}

local function dropLastCharacter(text)
  local first = #text
  while first > 1 do
    local byte = text:byte(first)
    if not byte or byte < 0x80 or byte > 0xBF then break end
    first = first - 1
  end
  return text:sub(1, first - 1)
end

local function fit(Font, value, maximum)
  local text = tostring(value or "----")
  if Font.width(text) <= maximum then return text end
  local suffix = "."
  while text ~= "" and Font.width(text .. suffix) > maximum do
    text = dropLastCharacter(text)
  end
  return text .. suffix
end

local function fieldBlock(Font, field, maximum)
  local label = fit(Font, tostring(field.label or "----"):upper(), maximum)
  local value = fit(Font, field.value, maximum)
  local lines
  if Font.width(label) + 8 + Font.width(value) <= maximum then
    local gap = math.max(1, math.floor((maximum
      - Font.width(label) - Font.width(value)) / 8))
    lines = { label .. string.rep(" ", gap) .. value }
  else
    lines = { label, value }
  end
  return {
    kind = "field",
    label = label,
    value = value,
    lines = lines,
  }
end

local function pokemonBlock(Font, mon, maximum)
  local level = math.max(0, math.floor(tonumber(mon.level) or 0))
  local hp = math.max(0, math.floor(tonumber(mon.hp) or 0))
  local maxHp = math.max(0, math.floor(tonumber(mon.maxHp) or 0))
  return {
    kind = "pokemon",
    lines = {
      fit(Font, mon.name, maximum),
      fit(Font, ("LV%d   HP %d/%d"):format(level, hp, maxHp), maximum),
    },
  }
end

local function paginate(blocks, rowsPerPage)
  local pages, page, used = {}, {}, 0
  for _, block in ipairs(blocks) do
    local rows = #block.lines
    if used > 0 and used + rows > rowsPerPage then
      pages[#pages + 1] = page
      page, used = {}, 0
    end
    page[#page + 1] = block
    used = used + rows
  end
  if #page > 0 or #pages == 0 then pages[#pages + 1] = page end
  return pages
end

function StateDetailsView.factory(opts)
  opts = opts or {}
  local rowsPerPage = opts.rowsPerPage or 12
  local maximum = opts.maximumWidth or 144

  local Details = {}

  function Details.new(mod, game, model)
    model = model or {}
    local Font = assert(mod.ui and mod.ui.Font,
      "StateDetailsView needs public mod.ui.Font")
    local view = mod.ui.ListMenu.new(game, model.title or "STATE DETAILS", {})
    view.index = nil
    view.blocks = {}
    for _, field in ipairs(model.fields or {}) do
      view.blocks[#view.blocks + 1] = fieldBlock(Font, field, maximum)
    end
    for _, mon in ipairs(model.party or {}) do
      view.blocks[#view.blocks + 1] = pokemonBlock(Font, mon, maximum)
    end
    view.pages = paginate(view.blocks, rowsPerPage)
    view.page = 1

    function view:update()
      local input = self.game and self.game.input
      if not input then return end
      if input:wasPressed("left") or input:wasPressed("up") then
        self.page = math.max(1, self.page - 1)
      elseif input:wasPressed("right") or input:wasPressed("down") then
        self.page = math.min(#self.pages, self.page + 1)
      elseif input:wasPressed("a") or input:wasPressed("b") then
        self:close()
      end
    end

    function view:draw()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(self.title, 8, 4)
      local y = 20
      for _, block in ipairs(self.pages[self.page] or {}) do
        for _, line in ipairs(block.lines) do
          Font.draw(line, 8, y)
          y = y + 8
        end
      end
      if #self.pages > 1 then
        local pageLabel = ("%d/%d"):format(self.page, #self.pages)
        Font.draw(pageLabel, 152 - Font.width(pageLabel), 132)
      end
      Font.draw("A/B BACK", 8, 132)
      love.graphics.setColor(1, 1, 1, 1)
    end

    return view
  end

  return Details
end

return StateDetailsView.factory
