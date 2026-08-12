local HistoryView = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function HistoryView.factory(config)
  config = config or {}
  local rowLimit = config.visualRows or 7

  local History = {}

  function History.new(mod, game, title, items, opts)
    opts = opts or {}
    local Font = assert(mod.ui and mod.ui.Font, "HistoryView needs public mod.ui.Font")
    local view = mod.ui.ListMenu.new(game, title, items, {})
    view.index = #items > 0 and 1 or nil
    view.holdDir, view.holdFrames = nil, 0

    local function dateFor(item)
      local ok, value = pcall(opts.dateFor or function() return "DATE UNKNOWN" end, item)
      if not ok or type(value) ~= "string" or value == "" or value == "----" then
        return "DATE UNKNOWN"
      end
      return value
    end

    function view:_allVisualRows()
      local rows, previous = {}, nil
      for itemIndex, item in ipairs(self.items) do
        local date = dateFor(item)
        if date ~= previous then
          rows[#rows + 1] = { kind = "header", text = date }
          previous = date
        end
        rows[#rows + 1] = { kind = "state", item = item, itemIndex = itemIndex }
      end
      return rows
    end

    function view:visibleRows()
      local rows = self:_allVisualRows()
      if #rows <= rowLimit or self.index == nil then return rows end
      local selected = 1
      for rowIndex, row in ipairs(rows) do
        if row.kind == "state" and row.itemIndex == self.index then
          selected = rowIndex
          break
        end
      end
      local start = clamp(selected - math.floor(rowLimit / 2), 1,
        math.max(1, #rows - rowLimit + 1))
      if start > 1 and rows[start].kind == "state"
          and rows[start - 1].kind == "header" then
        start = start - 1
      end
      local out = {}
      for index = start, math.min(#rows, start + rowLimit - 1) do
        out[#out + 1] = rows[index]
      end
      return out
    end

    function view:moveSelection(delta)
      if #self.items == 0 then return end
      self.index = clamp((self.index or 1) + delta, 1, #self.items)
    end

    function view:selectCurrent()
      if self.index and opts.onChoose then
        return opts.onChoose(self.items[self.index], self)
      end
    end

    function view:back()
      self:close()
      if opts.onCancel then return opts.onCancel() end
    end

    function view:modernModel()
      local rows, selected = {}, 1
      for _, row in ipairs(self:_allVisualRows()) do
        if row.kind == "header" then
          rows[#rows + 1] = {
            label = row.text, header = true, enabled = false,
          }
        else
          local item = row.item or {}
          rows[#rows + 1] = {
            label = item.label,
            value = item.right,
            enabled = item.enabled ~= false,
          }
          if row.itemIndex == self.index then selected = #rows end
        end
      end
      return {
        title = self.title,
        rows = rows,
        index = selected,
        footer = { "A SELECT", "B BACK" },
      }
    end

    function view:update()
      local input = self.game and self.game.input
      if not input then return end
      if input:wasPressed("up") then
        self:moveSelection(-1)
        self.holdDir, self.holdFrames = "up", 0
      elseif input:wasPressed("down") then
        self:moveSelection(1)
        self.holdDir, self.holdFrames = "down", 0
      elseif input:wasPressed("left") then
        self:moveSelection(-5)
      elseif input:wasPressed("right") then
        self:moveSelection(5)
      elseif input:wasPressed("b") then
        return self:back()
      elseif input:wasPressed("a") and self.index then
        return self:selectCurrent()
      end
      local dir = self.holdDir
      if dir and input.isDown and input:isDown(dir) then
        self.holdFrames = self.holdFrames + 1
        if self.holdFrames >= 16 and (self.holdFrames - 16) % 4 == 0 then
          self:moveSelection(dir == "up" and -1 or 1)
        end
      elseif dir then
        self.holdDir, self.holdFrames = nil, 0
      end
    end

    function view:draw()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(self.title, 8, 4)
      for position, row in ipairs(self:visibleRows()) do
        local y = 8 + position * 16
        if row.kind == "header" then
          Font.draw(row.text, 8, y)
        else
          Font.draw(row.item.label, 16, y)
          if row.item.right then
            Font.draw(row.item.right, 152 - Font.width(row.item.right), y)
          end
          if row.itemIndex == self.index then
            local cursor = mod.ui.Theme and mod.ui.Theme.cursor
            if cursor and Font.drawCode then Font.drawCode(cursor, 8, y)
            else Font.draw(">", 8, y) end
          end
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end

    return view
  end

  return History
end

return HistoryView.factory
