local StartMenuIntegration = {}

function StartMenuIntegration.install(mod, service, rootScreen)
  return mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    mod.ui.insertBefore(out, "OPTION", {
      label = "QUICKSAVE",
      onSelect = function() service:quickSave(game) end,
    })
    mod.ui.insertBefore(out, "OPTION", {
      label = "STATES",
      onSelect = function() mod.ui.push(game, rootScreen) end,
    })
    return out
  end)
end

return StartMenuIntegration
