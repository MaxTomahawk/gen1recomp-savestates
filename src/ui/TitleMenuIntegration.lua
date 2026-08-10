-- Title-state history is intentionally a distinct context: it resolves the
-- launcher-selected existing playthrough through the public selected-storage
-- contract, rather than treating the fresh title skeleton as a New Game.
local TitleMenuIntegration = {}

function TitleMenuIntegration.install(mod, rootScreen)
  return mod.hooks:wrap("ui.title_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    mod.ui.insertBefore(out, "NEW GAME", {
      label = "SAVE STATES",
      onSelect = function()
        mod.ui.push(game, rootScreen, { context = "title" })
      end,
    })
    return out
  end)
end

return TitleMenuIntegration
