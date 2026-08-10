-- Title-state history is intentionally a distinct context: it resolves the
-- launcher-selected existing playthrough through the public selected-storage
-- contract, rather than treating the fresh title skeleton as a New Game.
local TitleMenuIntegration = {}

local function enabled(callback)
  if type(callback) ~= "function" then return false end
  local ok, value = pcall(callback)
  return ok and value == true
end

local function newestResumeCandidate(service, game)
  if type(service) ~= "table" or type(service.titleLatestResumeCandidate) ~= "function" then
    return nil
  end
  local ok, snapshot = pcall(service.titleLatestResumeCandidate, service, game)
  if not ok or type(snapshot) ~= "table" or type(snapshot.metadata) ~= "table"
      or type(snapshot.metadata.id) ~= "string" or snapshot.metadata.id == "" then
    return nil
  end
  return snapshot
end

local function resume(service, game, id)
  if type(service) ~= "table" or type(service.resumeTitleState) ~= "function" then return end
  pcall(service.resumeTitleState, service, game, id)
end

-- CONTINUE LATEST is source-owned policy over the generic selected-storage and
-- checkpoint-resume contracts.  It decorates the public returned item list;
-- when disabled, no title storage is touched and vanilla callbacks remain
-- exactly as the engine/other decorators returned them.
function TitleMenuIntegration.install(mod, service, rootScreen, continueLatestEnabled)
  return mod.hooks:wrap("ui.title_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    if enabled(continueLatestEnabled) then
      local latest = newestResumeCandidate(service, game)
      if latest then
        local continueItem
        for _, item in ipairs(out) do
          if type(item) == "table" and item.label == "CONTINUE" then
            continueItem = item
            break
          end
        end
        local action = function()
          resume(service, game, latest.metadata.id)
        end
        if continueItem then
          continueItem.onSelect = action
        else
          mod.ui.insertBefore(out, "NEW GAME", { label = "CONTINUE", onSelect = action })
        end
      end
    end
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
