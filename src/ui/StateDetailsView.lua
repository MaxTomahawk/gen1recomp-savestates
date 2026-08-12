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
    height = #lines * 8,
  }
end

local function pokemonBlock(Font, mon, maximum)
  local level = math.max(0, math.floor(tonumber(mon.level) or 0))
  local hp = math.max(0, math.floor(tonumber(mon.hp) or 0))
  local maxHp = math.max(0, math.floor(tonumber(mon.maxHp) or 0))
  return {
    kind = "pokemon",
    mon = mon,
    lines = {
      fit(Font, mon.name, maximum),
      fit(Font, ("LV%d HP %d/%d"):format(level, hp, maxHp), maximum),
    },
    height = 16,
  }
end

function StateDetailsView.factory(opts)
  opts = opts or {}
  local maximum = opts.maximumWidth or 144
  local viewportTop = opts.viewportTop or 20
  local viewportBottom = opts.viewportBottom or 124

  local Details = {}

  function Details.new(mod, game, model)
    model = model or {}
    local Font = assert(mod.ui and mod.ui.Font,
      "StateDetailsView needs public mod.ui.Font")
    local view = mod.ui.ListMenu.new(game, model.title or "STATE DETAILS", {})
    view.blocks, view.partyBlocks = {}, {}
    view.blink, view.scrollY = 0, 0
    for _, field in ipairs(model.fields or {}) do
      view.blocks[#view.blocks + 1] = fieldBlock(Font, field, maximum)
    end
    for _, mon in ipairs(model.party or {}) do
      local block = pokemonBlock(Font, mon, maximum - 16)
      block.partyIndex = #view.partyBlocks + 1
      view.partyBlocks[#view.partyBlocks + 1] = block
      view.blocks[#view.blocks + 1] = block
    end
    view.index = #view.partyBlocks > 0 and 1 or nil

    local function blockTop(self, wanted)
      local y = 0
      for _, block in ipairs(self.blocks) do
        if block == wanted then return y end
        y = y + block.height
      end
      return y
    end

    function view:_keepSelectionVisible()
      if not self.index then return end
      local selected = self.partyBlocks[self.index]
      local top = blockTop(self, selected)
      local height = viewportBottom - viewportTop
      if top < self.scrollY then self.scrollY = top end
      if top + selected.height > self.scrollY + height then
        self.scrollY = top + selected.height - height
      end
    end

    function view:moveSelection(delta)
      if not self.index or #self.partyBlocks == 0 then return end
      self.index = ((self.index - 1 + delta) % #self.partyBlocks) + 1
      self:_keepSelectionVisible()
    end

    function view:back()
      return self:close()
    end

    function view:modernModel()
      local rows, selected = {}, 1
      for _, block in ipairs(self.blocks) do
        if block.kind == "pokemon" then
          rows[#rows + 1] = {
            label = block.lines[1],
            value = block.lines[2],
            species = block.mon.species,
            hp = block.mon.hp,
            maxHp = block.mon.maxHp,
          }
          if block.partyIndex == self.index then selected = #rows end
        else
          rows[#rows + 1] = {
            label = block.label,
            value = block.value,
            enabled = false,
          }
        end
      end
      return {
        title = self.title,
        rows = rows,
        index = selected,
        footer = { "UP/DOWN PARTY", "A/B BACK" },
      }
    end

    function view:update()
      local input = self.game and self.game.input
      if not input then return end
      self.blink = (self.blink + 1) % 320
      if self.index and input:wasPressed("up") then
        self:moveSelection(-1)
      elseif self.index and input:wasPressed("down") then
        self:moveSelection(1)
      elseif input:wasPressed("a") or input:wasPressed("b") then
        self:back()
      end
    end

    function view:draw()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(self.title, 8, 4)
      local logicalY = 0
      for _, block in ipairs(self.blocks) do
        local y = viewportTop + logicalY - self.scrollY
        if y + block.height > viewportTop and y < viewportBottom then
          if block.kind == "pokemon" then
            local selected = block.partyIndex == self.index
            local icon = mod.ui and mod.ui.PokemonIcon
            local iconDrawn = false
            if icon and type(icon.draw) == "function" and block.mon.species then
              local ok, result = pcall(icon.draw, self.game, {
                species = block.mon.species,
                hp = block.mon.hp,
                maxHp = block.mon.maxHp,
              }, 8, y, { selected = selected, counter = self.blink })
              iconDrawn = ok and result ~= false
            end
            local textX = iconDrawn and 24 or 16
            Font.draw(block.lines[1], textX, y)
            Font.draw(block.lines[2], textX, y + 8)
            if selected then
              local cursor = mod.ui.Theme and mod.ui.Theme.cursor
              if cursor and Font.drawCode then Font.drawCode(cursor, 0, y + 8)
              else Font.draw(">", 0, y + 8) end
            end
          else
            for lineIndex, line in ipairs(block.lines) do
              Font.draw(line, 8, y + (lineIndex - 1) * 8)
            end
          end
        end
        logicalY = logicalY + block.height
      end
      Font.draw("A/B BACK", 8, 132)
      love.graphics.setColor(1, 1, 1, 1)
    end

    return view
  end

  return Details
end

return StateDetailsView.factory
